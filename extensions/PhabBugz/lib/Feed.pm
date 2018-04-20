# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Feed;

use 5.10.1;

use IO::Async::Timer::Periodic;
use IO::Async::Loop;
use List::Util qw(first);
use List::MoreUtils qw(any);
use Moo;
use Try::Tiny;

use Bugzilla::Logging;
use Bugzilla::Constants;
use Bugzilla::Search;
use Bugzilla::Util qw(diff_arrays with_writable_database with_readonly_database);

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Policy;
use Bugzilla::Extension::PhabBugz::Revision;
use Bugzilla::Extension::PhabBugz::User;
use Bugzilla::Extension::PhabBugz::Util qw(
    add_security_sync_comments
    create_revision_attachment
    get_bug_role_phids
    get_phab_bmo_ids
    get_project_phid
    get_security_sync_groups
    is_attachment_phab_revision
    make_revision_public
    request
    set_phab_user
);

has 'is_daemon' => ( is => 'rw', default => 0 );

sub start {
    my ($self) = @_;

    # Query for new revisions or changes
    my $feed_timer = IO::Async::Timer::Periodic->new(
        first_interval => 0,
        interval       => PHAB_FEED_POLL_SECONDS,
        reschedule     => 'drift',
        on_tick        => sub { 
            try{
                $self->feed_query();
            }
            catch {
                FATAL($_);
            };
            Bugzilla->_cleanup();
        },
    );

    # Query for new users
    my $user_timer = IO::Async::Timer::Periodic->new(
        first_interval => 0,
        interval       => PHAB_USER_POLL_SECONDS,
        reschedule     => 'drift',
        on_tick        => sub { 
            try{
                $self->user_query();
            }
            catch {
                FATAL($_);
            };
            Bugzilla->_cleanup();
        },
    );

    my $loop = IO::Async::Loop->new;
    $loop->add($feed_timer);
    $loop->add($user_timer);
    $feed_timer->start;
    $user_timer->start;
    $loop->run;
}

sub feed_query {
    my ($self) = @_;

    # Ensure Phabricator syncing is enabled
    if (!Bugzilla->params->{phabricator_enabled}) {
        INFO("PHABRICATOR SYNC DISABLED");
        return;
    }

    # PROCESS NEW FEED TRANSACTIONS

    INFO("FEED: Fetching new transactions");

    my $story_last_id = $self->get_last_id('feed');

    # Check for new transctions (stories)
    my $new_stories = $self->new_stories($story_last_id);
    INFO("FEED: No new stories") unless @$new_stories;

    # Process each story
    foreach my $story_data (@$new_stories) {
        my $story_id    = $story_data->{id};
        my $story_phid  = $story_data->{phid};
        my $author_phid = $story_data->{authorPHID};
        my $object_phid = $story_data->{objectPHID};
        my $story_text  = $story_data->{text};

        DEBUG("STORY ID: $story_id");
        DEBUG("STORY PHID: $story_phid");
        DEBUG("AUTHOR PHID: $author_phid");
        DEBUG("OBJECT PHID: $object_phid");
        INFO("STORY TEXT: $story_text");

        # Only interested in changes to revisions for now.
        if ($object_phid !~ /^PHID-DREV/) {
            DEBUG("SKIPPING: Not a revision change");
            $self->save_last_id($story_id, 'feed');
            next;
        }

        # Skip changes done by phab-bot user
        my $phab_users = get_phab_bmo_ids({ phids => [$author_phid] });
        if (@$phab_users) {
            my $user = Bugzilla::User->new({ id => $phab_users->[0]->{id}, cache => 1 });
            if ($user->login eq PHAB_AUTOMATION_USER) {
                DEBUG("SKIPPING: Change made by phabricator user");
                $self->save_last_id($story_id, 'feed');
                next;
            }
        }

        with_writable_database {
            $self->process_revision_change($object_phid, $story_text);
        };
        $self->save_last_id($story_id, 'feed');
    }
}

sub user_query {
    my ( $self ) = @_;

    # Ensure Phabricator syncing is enabled
    if (!Bugzilla->params->{phabricator_enabled}) {
        INFO("PHABRICATOR SYNC DISABLED");
        return;
    }

    # PROCESS NEW USERS

    INFO("USERS: Fetching new users");

    my $user_last_id = $self->get_last_id('user');

    # Check for new users
    my $new_users = $self->new_users($user_last_id);
    INFO("FEED: No new users") unless @$new_users;

    # Process each new user
    foreach my $user_data (@$new_users) {
        my $user_id       = $user_data->{id};
        my $user_login    = $user_data->{fields}{username};
        my $user_realname = $user_data->{fields}{realName};
        my $object_phid   = $user_data->{phid};

        DEBUG("USER ID: $user_id");
        DEBUG("USER LOGIN: $user_login");
        DEBUG("USER REALNAME: $user_realname");
        DEBUG("OBJECT PHID: $object_phid");

        with_readonly_database {
            $self->process_new_user($user_data);
        };
        $self->save_last_id($user_id, 'user');
    }
}

sub process_revision_change {
    my ($self, $revision_phid, $story_text) = @_;

    # Load the revision from Phabricator
    my $revision = Bugzilla::Extension::PhabBugz::Revision->new_from_query({ phids => [ $revision_phid ] });

    # NO BUG ID

    if (!$revision->bug_id) {
        if ($story_text =~ /\s+created\s+D\d+/) {
            # If new revision and bug id was omitted, make revision public
            DEBUG("No bug associated with new revision. Marking public.");
            $revision->set_policy('view', 'public');
            $revision->set_policy('edit', 'users');
            $revision->update();
            INFO("SUCCESS");
            return;
        }
        else {
            DEBUG("SKIPPING: No bug associated with revision change");
            return;
        }
    }

    my $log_message = sprintf(
        "REVISION CHANGE FOUND: D%d: %s | bug: %d | %s",
        $revision->id,
        $revision->title,
        $revision->bug_id,
        $story_text);
    INFO($log_message);

    # Pre setup before making changes
    my $old_user = set_phab_user();
    my $bug = Bugzilla::Bug->new({ id => $revision->bug_id, cache => 1 });

    # REVISION SECURITY POLICY

    # If bug is public then remove privacy policy
    if (!@{ $bug->groups_in }) {
        DEBUG('Bug is public so setting view/edit public');
        $revision->set_policy('view', 'public');
        $revision->set_policy('edit', 'users');
        my $secure_project_phid = get_project_phid('secure-revision');
        $revision->remove_project($secure_project_phid);
    }
    # else bug is private.
    else {
        my @set_groups = get_security_sync_groups($bug);

        # If bug privacy groups do not have any matching synchronized groups,
        # then leave revision private and it will have be dealt with manually.
        if (!@set_groups) {
            DEBUG('No matching groups. Adding comments to bug and revision');
            add_security_sync_comments([$revision], $bug);
        }
        # Otherwise, we create a new custom policy containing the project
        # groups that are mapped to bugzilla groups.
        else {
            my @set_projects = map { "bmo-" . $_ } @set_groups;

            # If current policy projects matches what we want to set, then
            # we leave the current policy alone.
            my $current_policy;
            if ($revision->view_policy =~ /^PHID-PLCY/) {
                DEBUG("Loading current policy: " . $revision->view_policy);
                $current_policy
                    = Bugzilla::Extension::PhabBugz::Policy->new_from_query({ phids => [ $revision->view_policy ]});
                my $current_projects = $current_policy->rule_projects;
                DEBUG("Current policy projects: " . join(", ", @$current_projects));
                my ($added, $removed) = diff_arrays($current_projects, \@set_projects);
                if (@$added || @$removed) {
                    DEBUG('Project groups do not match. Need new custom policy');
                    $current_policy = undef;
                }
                else {
                    DEBUG('Project groups match. Leaving current policy as-is');
                }
            }

            if (!$current_policy) {
                DEBUG("Creating new custom policy: " . join(", ", @set_projects));
                my $new_policy = Bugzilla::Extension::PhabBugz::Policy->create(\@set_projects);
                $revision->set_policy('view', $new_policy->phid);
                $revision->set_policy('edit', $new_policy->phid);
            }

            my $secure_project_phid = get_project_phid('secure-revision');
            $revision->add_project($secure_project_phid);
        }

        # Subscriber list of the private revision should always match
        # the bug roles such as assignee, qa contact, and cc members.
        my $subscribers = get_bug_role_phids($bug);
        $revision->set_subscribers($subscribers);
    }

    my ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");

    my $attachment = create_revision_attachment($bug, $revision, $timestamp);

    # ATTACHMENT OBSOLETES

    # fixup attachments on current bug
    my @attachments =
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

    foreach my $attachment (@attachments) {
        my ($attach_revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
        next if $attach_revision_id != $revision->id;

        my $make_obsolete = $revision->status eq 'abandoned' ? 1 : 0;
        DEBUG('Updating obsolete status on attachmment ' . $attachment->id);
        $attachment->set_is_obsolete($make_obsolete);

        if ($revision->title ne $attachment->description) {
            DEBUG('Updating description on attachment ' . $attachment->id);
            $attachment->set_description($revision->title);
        }

        $attachment->update($timestamp);
    }

    # fixup attachments with same revision id but on different bugs
    my %other_bugs;
    my $other_attachments = Bugzilla::Attachment->match({
        mimetype => PHAB_CONTENT_TYPE,
        filename => 'phabricator-D' . $revision->id . '-url.txt',
        WHERE    => { 'bug_id != ? AND NOT isobsolete' => $bug->id }
    });
    foreach my $attachment (@$other_attachments) {
        $other_bugs{$attachment->bug_id}++;
        DEBUG('Updating obsolete status on attachment ' .
                             $attachment->id . " for bug " . $attachment->bug_id);
        $attachment->set_is_obsolete(1);
        $attachment->update($timestamp);
    }

    # REVIEWER STATUSES

    my (@accepted_phids, @denied_phids, @accepted_user_ids, @denied_user_ids);
    unless ($revision->status eq 'changes-planned' || $revision->status eq 'needs-review') {
        foreach my $reviewer (@{ $revision->reviewers }) {
            push(@accepted_phids, $reviewer->phab_phid) if $reviewer->phab_review_status eq 'accepted';
            push(@denied_phids, $reviewer->phab_phid) if $reviewer->phab_review_status eq 'rejected';
        }
    }

    my $phab_users = get_phab_bmo_ids({ phids => \@accepted_phids });
    @accepted_user_ids = map { $_->{id} } @$phab_users;
    $phab_users = get_phab_bmo_ids({ phids => \@denied_phids });
    @denied_user_ids = map { $_->{id} } @$phab_users;

    my %reviewers_hash =  map { $_->name => 1 } @{ $revision->reviewers };

    foreach my $attachment (@attachments) {
        my ($attach_revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
        next if $revision->id != $attach_revision_id;

        # Clear old flags if no longer accepted
        my (@denied_flags, @new_flags, @removed_flags, %accepted_done, $flag_type);
        foreach my $flag (@{ $attachment->flags }) {
            next if $flag->type->name ne 'review';
            $flag_type = $flag->type if $flag->type->is_active;
            if (any { $flag->setter->id == $_ } @denied_user_ids) {
                push(@denied_flags, { id => $flag->id, setter => $flag->setter, status => 'X' });
            }
            if (any { $flag->setter->id == $_ } @accepted_user_ids) {
                $accepted_done{$flag->setter->id}++;
            }
            if ($flag->status eq '+'
                && !any { $flag->setter->id == $_ } (@accepted_user_ids, @denied_user_ids)) {
                push(@removed_flags, { id => $flag->id, setter => $flag->setter, status => 'X' });
            }
        }

        $flag_type ||= first { $_->name eq 'review' && $_->is_active } @{ $attachment->flag_types };

        # Create new flags
        foreach my $user_id (@accepted_user_ids) {
            next if $accepted_done{$user_id};
            my $user = Bugzilla::User->check({ id => $user_id, cache => 1 });
            push(@new_flags, { type_id => $flag_type->id, setter => $user, status => '+' });
        }

        # Also add comment to for attachment update showing the user's name
        # that changed the revision.
        my $comment;
        foreach my $flag_data (@new_flags) {
            $comment .= $flag_data->{setter}->name . " has approved the revision.\n";
        }
        foreach my $flag_data (@denied_flags) {
            $comment .= $flag_data->{setter}->name . " has requested changes to the revision.\n";
        }
        foreach my $flag_data (@removed_flags) {
            if ( exists $reviewers_hash{$flag_data->{setter}->name} ) {
                $comment .= "Flag set by " . $flag_data->{setter}->name . " is no longer active.\n";
            } else {
                $comment .= $flag_data->{setter}->name . " has been removed from the revision.\n";
            }
        }

        if ($comment) {
            $comment .= "\n" . Bugzilla->params->{phabricator_base_uri} . "D" . $revision->id;
            # Add transaction_id as anchor if one present
            # $comment .= "#" . $params->{transaction_id} if $params->{transaction_id};
            $bug->add_comment($comment, {
                isprivate  => $attachment->isprivate,
                type       => CMT_ATTACHMENT_UPDATED,
                extra_data => $attachment->id
            });
        }

        $attachment->set_flags([ @denied_flags, @removed_flags ], \@new_flags);
        $attachment->update($timestamp);
    }

    # FINISH UP

    $bug->update($timestamp);
    $revision->update();

    # Email changes for this revisions bug and also for any other
    # bugs that previously had these revision attachments
    foreach my $bug_id ($revision->bug_id, keys %other_bugs) {
        Bugzilla::BugMail::Send($bug_id, { changer => Bugzilla->user });
    }

    Bugzilla->set_user($old_user);

    INFO('SUCCESS: Revision D' . $revision->id . ' processed');
}

sub process_new_user {
    my ( $self, $user_data ) = @_;

    # Load the user data into a proper object
    my $phab_user = Bugzilla::Extension::PhabBugz::User->new($user_data);

    if (!$phab_user->bugzilla_id) {
        DEBUG("SKIPPING: No bugzilla id associated with user");
        return;
    }

    my $bug_user  = $phab_user->bugzilla_user;

    # Pre setup before querying DB
    my $old_user = set_phab_user();

    my $params = {
        f3  => 'OP',
        j3  => 'OR',

        # User must be either reporter, assignee, qa_contact
        # or on the cc list of the bug
        f4  => 'cc',
        o4  => 'equals',
        v4  => $bug_user->login,

        f5  => 'assigned_to',
        o5  => 'equals',
        v5  => $bug_user->login,

        f6  => 'qa_contact',
        o6  => 'equals',
        v6  => $bug_user->login,

        f7  => 'reporter',
        o7  => 'equals',
        v7  => $bug_user->login,

        f9  => 'CP',

        # The bug needs to be private
        f10 => 'bug_group',
        o10 => 'isnotempty',

        # And the bug must have one or more attachments
        # that are connected to revisions
        f11 => 'attachments.filename',
        o11 => 'regexp',
        v11 => '^phabricator-D[[:digit:]]+-url[[.period.]]txt$',
    };

    my $search = Bugzilla::Search->new( fields => [ 'bug_id' ],
                                        params => $params,
                                        order  => [ 'bug_id' ] );
    my $data = $search->data;

    # the first value of each row should be the bug id
    my @bug_ids = map { shift @$_ } @$data;

    foreach my $bug_id (@bug_ids) {
        DEBUG("Processing bug $bug_id");

        my $bug = Bugzilla::Bug->new({ id => $bug_id, cache => 1 });

        my @attachments =
            grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

        foreach my $attachment (@attachments) {
            my ($revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
            DEBUG("Processing revision D$revision_id");

            my $revision = Bugzilla::Extension::PhabBugz::Revision->new_from_query(
                { ids => [ int($revision_id) ] });

            $revision->add_subscriber($phab_user->phid);
            $revision->update();

            DEBUG("Revision $revision_id updated");
        }
    }

    Bugzilla->set_user($old_user);

    INFO('SUCCESS: User ' . $phab_user->id . ' processed');
}

##################
# Helper Methods #
##################

sub new_stories {
    my ( $self, $after ) = @_;
    my $data = { view => 'text' };
    $data->{after} = $after if $after;
    my $result = request( 'feed.query_id', $data );
    unless ( ref $result->{result}{data} eq 'ARRAY'
        && @{ $result->{result}{data} } )
    {
        return [];
    }

    # Guarantee that the data is in ascending ID order
    return [ sort { $a->{id} <=> $b->{id} } @{ $result->{result}{data} } ];
}

sub new_users {
    my ( $self, $after ) = @_;
    my $data = {
        order       => [ "id" ],
        attachments => {
            'external-accounts' => 1
        }
    };
    $data->{before} = $after if $after;
    my $result = request( 'user.search', $data );
    unless ( ref $result->{result}{data} eq 'ARRAY'
        && @{ $result->{result}{data} } )
    {
        return [];
    }

    # Guarantee that the data is in ascending ID order
    return [ sort { $a->{id} <=> $b->{id} } @{ $result->{result}{data} } ];
}

sub get_last_id {
    my ( $self, $type ) = @_;
    my $type_full = $type . "_last_id";
    my $last_id   = Bugzilla->dbh->selectrow_array( "
        SELECT value FROM phabbugz WHERE name = ?", undef, $type_full );
    $last_id ||= 0;
    DEBUG( "QUERY " . uc($type_full) . ": $last_id" );
    return $last_id;
}

sub save_last_id {
    my ( $self, $last_id, $type ) = @_;

    # Store the largest last key so we can start from there in the next session
    my $type_full = $type . "_last_id";
    DEBUG( "UPDATING " . uc($type_full) . ": $last_id" );
    Bugzilla->dbh->do( "REPLACE INTO phabbugz (name, value) VALUES (?, ?)",
        undef, $type_full, $last_id );
}

1;
