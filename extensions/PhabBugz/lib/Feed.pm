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
use List::MoreUtils qw(any uniq);
use Moo;
use Scalar::Util qw(blessed);
use Try::Tiny;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Logging;
use Bugzilla::Mailer;
use Bugzilla::Search;
use Bugzilla::Util qw(diff_arrays format_time with_writable_database with_readonly_database);

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Policy;
use Bugzilla::Extension::PhabBugz::Revision;
use Bugzilla::Extension::PhabBugz::User;
use Bugzilla::Extension::PhabBugz::Util qw(
    add_security_sync_comments
    create_revision_attachment
    get_bug_role_phids
    get_security_sync_groups
    is_attachment_phab_revision
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

    # Update project membership in Phabricator based on Bugzilla groups
    my $group_timer = IO::Async::Timer::Periodic->new(
        first_interval => 0,
        interval       => PHAB_GROUP_POLL_SECONDS,
        reschedule     => 'drift',
        on_tick        => sub {
            try{
                $self->group_query();
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
    $loop->add($group_timer);
    $feed_timer->start;
    $user_timer->start;
    $group_timer->start;
    $loop->run;
}

sub feed_query {
    my ($self) = @_;

    local Bugzilla::Logging->fields->{type} = 'FEED';

    # Ensure Phabricator syncing is enabled
    if (!Bugzilla->params->{phabricator_enabled}) {
        WARN("PHABRICATOR SYNC DISABLED");
        return;
    }

    # PROCESS NEW FEED TRANSACTIONS

    INFO("Fetching new stories");

    my $story_last_id = $self->get_last_id('feed');

    # Check for new transctions (stories)
    my $new_stories = $self->new_stories($story_last_id);
    INFO("No new stories") unless @$new_stories;

    # Process each story
    foreach my $story_data (@$new_stories) {
        my $story_id    = $story_data->{id};
        my $story_phid  = $story_data->{phid};
        my $author_phid = $story_data->{authorPHID};
        my $object_phid = $story_data->{objectPHID};
        my $story_text  = $story_data->{text};

        TRACE("STORY ID: $story_id");
        TRACE("STORY PHID: $story_phid");
        TRACE("AUTHOR PHID: $author_phid");
        TRACE("OBJECT PHID: $object_phid");
        INFO("STORY TEXT: $story_text");

        # Only interested in changes to revisions for now.
        if ($object_phid !~ /^PHID-DREV/) {
            INFO("SKIPPING: Not a revision change");
            $self->save_last_id($story_id, 'feed');
            next;
        }

        # Skip changes done by phab-bot user
        my $phab_user = Bugzilla::Extension::PhabBugz::User->new_from_query(
          {
            phids => [ $author_phid ]
          }
        );

        if ($phab_user && $phab_user->bugzilla_id) {
            if ($phab_user->bugzilla_user->login eq PHAB_AUTOMATION_USER) {
                INFO("SKIPPING: Change made by phabricator user");
                $self->save_last_id($story_id, 'feed');
                next;
            }
        }

        with_writable_database {
            $self->process_revision_change($object_phid, $story_text);
        };
        $self->save_last_id($story_id, 'feed');
    }

    # Process any build targets as well.
    my $dbh = Bugzilla->dbh;

    INFO("Checking for revisions in draft mode");
    my $build_targets = $dbh->selectall_arrayref(
        "SELECT name, value FROM phabbugz WHERE name LIKE 'build_target_%'",
        { Slice => {} }
    );

    my $delete_build_target = $dbh->prepare(
        "DELETE FROM phabbugz WHERE name = ? AND VALUE = ?"
    );

    foreach my $target (@$build_targets) {
        my ($revision_id) = ($target->{name} =~ /^build_target_(\d+)$/);
        my $build_target  = $target->{value};

        next unless $revision_id && $build_target;

        INFO("Processing revision $revision_id with build target $build_target");

        my $revision =
          Bugzilla::Extension::PhabBugz::Revision->new_from_query(
            {
              ids => [ int($revision_id) ]
            }
        );

        with_writable_database {
            $self->process_revision_change($revision, " created D" . $revision->id);
        };

        # Set the build target to a passing status to
        # allow the revision to exit draft state
        request( 'harbormaster.sendmessage', {
            buildTargetPHID => $build_target,
            type            => 'pass'
        } );

        $delete_build_target->execute($target->{name}, $target->{value});
     }
}

sub user_query {
    my ( $self ) = @_;

    local Bugzilla::Logging->fields->{type} = 'USERS';

    # Ensure Phabricator syncing is enabled
    if (!Bugzilla->params->{phabricator_enabled}) {
        WARN("PHABRICATOR SYNC DISABLED");
        return;
    }

    # PROCESS NEW USERS

    INFO("Fetching new users");

    my $user_last_id = $self->get_last_id('user');

    # Check for new users
    my $new_users = $self->new_users($user_last_id);
    INFO("No new users") unless @$new_users;

    # Process each new user
    foreach my $user_data (@$new_users) {
        my $user_id       = $user_data->{id};
        my $user_login    = $user_data->{fields}{username};
        my $user_realname = $user_data->{fields}{realName};
        my $object_phid   = $user_data->{phid};

        TRACE("ID: $user_id");
        TRACE("LOGIN: $user_login");
        TRACE("REALNAME: $user_realname");
        TRACE("OBJECT PHID: $object_phid");

        with_readonly_database {
            $self->process_new_user($user_data);
        };
        $self->save_last_id($user_id, 'user');
    }
}

sub group_query {
    my ($self) = @_;

    local Bugzilla::Logging->fields->{type} = 'GROUPS';

    # Ensure Phabricator syncing is enabled
    if ( !Bugzilla->params->{phabricator_enabled} ) {
        WARN("PHABRICATOR SYNC DISABLED");
        return;
    }

    # PROCESS SECURITY GROUPS

    INFO("Updating group memberships");

    # Loop through each group and perform the following:
    #
    # 1. Load flattened list of group members
    # 2. Check to see if Phab project exists for 'bmo-<group_name>'
    # 3. Create if does not exist with locked down policy.
    # 4. Set project members to exact list including phab-bot user
    # 5. Profit

    my $sync_groups = Bugzilla::Group->match( { isactive => 1, isbuggroup => 1 } );

    # Load phab-bot Phabricator user to add as a member of each project group later
    my $phab_bmo_user = Bugzilla::User->new( { name => PHAB_AUTOMATION_USER, cache => 1 } );
    my $phab_user =
      Bugzilla::Extension::PhabBugz::User->new_from_query(
        {
            ids => [ $phab_bmo_user->id ]
        }
    );

    # secure-revision project that will be used for bmo group projects
    my $secure_revision =
      Bugzilla::Extension::PhabBugz::Project->new_from_query(
        {
          name => 'secure-revision'
        }
    );

    foreach my $group (@$sync_groups) {
        # Create group project if one does not yet exist
        my $phab_project_name = 'bmo-' . $group->name;
        my $project =
          Bugzilla::Extension::PhabBugz::Project->new_from_query(
            {
              name => $phab_project_name
            }
        );

        if ( !$project ) {
            INFO("Project $phab_project_name not found. Creating.");
            $project = Bugzilla::Extension::PhabBugz::Project->create(
              {
                name        => $phab_project_name,
                description => 'BMO Security Group for ' . $group->name,
                view_policy => $secure_revision->phid,
                edit_policy => $secure_revision->phid,
                join_policy => $secure_revision->phid
              }
            );
        }
        else {
            # Make sure that the group project permissions are set properly
            INFO("Updating permissions on $phab_project_name");
            $project->set_policy( 'view', $secure_revision->phid );
            $project->set_policy( 'edit', $secure_revision->phid );
            $project->set_policy( 'join', $secure_revision->phid );
        }

        # Make sure phab-bot also a member of the new project group so that it can
        # make policy changes to the private revisions
        INFO( "Checking project members for " . $project->name );
        my $set_members          = $self->get_group_members($group);
        my @set_member_phids     = uniq map { $_->phid } ( @$set_members, $phab_user );
        my @current_member_phids = uniq map { $_->phid } @{ $project->members };
        my ( $removed, $added )  = diff_arrays( \@current_member_phids, \@set_member_phids );

        if (@$added) {
            INFO( 'Adding project members: ' . join( ',', @$added ) );
            $project->add_member($_) foreach @$added;
        }

        if (@$removed) {
            INFO( 'Removing project members: ' . join( ',', @$removed ) );
            $project->remove_member($_) foreach @$removed;
        }

        if (@$added || @$removed) {
            my $result = $project->update();
            local Bugzilla::Logging->fields->{api_result} = $result;
            INFO( "Project " . $project->name . " updated" );
        }
    }
}

sub process_revision_change {
    my ($self, $revision_phid, $story_text) = @_;

    # Load the revision from Phabricator
    my $revision =
        blessed $revision_phid
        ? $revision_phid
        : Bugzilla::Extension::PhabBugz::Revision->new_from_query({ phids => [ $revision_phid ] });

    # NO BUG ID

    if (!$revision->bug_id) {
        if ($story_text =~ /\s+created\s+D\d+/) {
            # If new revision and bug id was omitted, make revision public
            INFO("No bug associated with new revision. Marking public.");
            $revision->make_public();
            $revision->update();
            INFO("SUCCESS");
            return;
        }
        else {
            INFO("SKIPPING: No bug associated with revision change");
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
        INFO('Bug is public so setting view/edit public');
        $revision->make_public();
    }
    # else bug is private.
    else {
        my @set_groups = get_security_sync_groups($bug);

        # If bug privacy groups do not have any matching synchronized groups,
        # then leave revision private and it will have be dealt with manually.
        if (!@set_groups) {
            INFO('No matching groups. Adding comments to bug and revision');
            add_security_sync_comments([$revision], $bug);
        }
        # Otherwise, we create a new custom policy containing the project
        # groups that are mapped to bugzilla groups.
        else {
            my $set_project_names = [ map { "bmo-" . $_ } @set_groups ];

            # If current policy projects matches what we want to set, then
            # we leave the current policy alone.
            my $current_policy;
            if ($revision->view_policy =~ /^PHID-PLCY/) {
                INFO("Loading current policy: " . $revision->view_policy);
                $current_policy
                    = Bugzilla::Extension::PhabBugz::Policy->new_from_query({ phids => [ $revision->view_policy ]});
                my $current_project_names = [ map { $_->name } @{ $current_policy->rule_projects } ];
                INFO("Current policy projects: " . join(", ", @$current_project_names));
                my ($added, $removed) = diff_arrays($current_project_names, $set_project_names);
                if (@$added || @$removed) {
                    INFO('Project groups do not match. Need new custom policy');
                    $current_policy = undef;
                }
                else {
                    INFO('Project groups match. Leaving current policy as-is');
                }
            }

            if (!$current_policy) {
                INFO("Creating new custom policy: " . join(", ", @$set_project_names));
                $revision->make_private($set_project_names);
            }

            # Subscriber list of the private revision should always match
            # the bug roles such as assignee, qa contact, and cc members.
            my $subscribers = get_bug_role_phids($bug);
            $revision->set_subscribers($subscribers);
        }
    }

    my ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");

    INFO('Checking for revision attachment');
    my $rev_attachment = create_revision_attachment($bug, $revision, $timestamp, $revision->author->bugzilla_user);
    INFO('Attachment ' . $rev_attachment->id . ' created or already exists.');

    # ATTACHMENT OBSOLETES

    # fixup attachments on current bug
    my @attachments =
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

    foreach my $attachment (@attachments) {
        my ($attach_revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
        next if $attach_revision_id != $revision->id;

        my $make_obsolete = $revision->status eq 'abandoned' ? 1 : 0;
        INFO('Updating obsolete status on attachmment ' . $attachment->id);
        $attachment->set_is_obsolete($make_obsolete);

        if ($revision->title ne $attachment->description) {
            INFO('Updating description on attachment ' . $attachment->id);
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
        INFO('Updating obsolete status on attachment ' .
             $attachment->id . " for bug " . $attachment->bug_id);
        $attachment->set_is_obsolete(1);
        $attachment->update($timestamp);
    }

    # REVIEWER STATUSES

    my (@accepted_phids, @denied_phids, @accepted_user_ids, @denied_user_ids);
    foreach my $reviewer (@{ $revision->reviewers }) {
        push(@accepted_phids, $reviewer->phid) if $reviewer->{phab_review_status} eq 'accepted';
        push(@denied_phids, $reviewer->phid) if $reviewer->{phab_review_status} eq 'rejected';
    }

    if ( @accepted_phids ) {
        my $phab_users = Bugzilla::Extension::PhabBugz::User->match(
          {
            phids => \@accepted_phids
          }
        );
        @accepted_user_ids = map { $_->bugzilla_user->id } grep { defined $_->bugzilla_user } @$phab_users;
    }

    if ( @denied_phids ) {
        my $phab_users = Bugzilla::Extension::PhabBugz::User->match(
          {
            phids => \@denied_phids
          }
        );
        @denied_user_ids = map { $_->bugzilla_user->id } grep { defined $_->bugzilla_user } @$phab_users;
    }

    my %reviewers_hash =  map { $_->name => 1 } @{ $revision->reviewers };

    foreach my $attachment (@attachments) {
        my ($attach_revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
        next if $revision->id != $attach_revision_id;

        # Clear old accepted review flags if no longer accepted
        my (@denied_flags, @new_flags, @removed_flags, %accepted_done, $flag_type);
        foreach my $flag (@{ $attachment->flags }) {
            next if $flag->type->name ne 'review';
            $flag_type = $flag->type if $flag->type->is_active;
            next if $flag->status ne '+';
            if (any { $flag->setter->id == $_ } @denied_user_ids) {
                INFO('Denying review flag set by ' . $flag->setter->name);
                push(@denied_flags, { id => $flag->id, setter => $flag->setter, status => 'X' });
            }
            if (any { $flag->setter->id == $_ } @accepted_user_ids) {
                INFO('Skipping as review+ already set by ' . $flag->setter->name);
                $accepted_done{$flag->setter->id}++;
            }
            if (!any { $flag->setter->id == $_ } (@accepted_user_ids, @denied_user_ids)) {
                INFO('Clearing review+ flag set by ' . $flag->setter->name);
                push(@removed_flags, { id => $flag->id, setter => $flag->setter, status => 'X' });
            }
        }

        $flag_type ||= first { $_->name eq 'review' && $_->is_active } @{ $attachment->flag_types };

        # Create new flags
        foreach my $user_id (@accepted_user_ids) {
            next if $accepted_done{$user_id};
            my $user = Bugzilla::User->check({ id => $user_id, cache => 1 });
            INFO('Setting new review+ flag for ' . $user->name);
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
            INFO("Flag comment: $comment");
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
        Bugzilla::BugMail::Send($bug_id, { changer => $rev_attachment->attacher });
    }

    Bugzilla->set_user($old_user);

    INFO('SUCCESS: Revision D' . $revision->id . ' processed');
}

sub process_new_user {
    my ( $self, $user_data ) = @_;

    # Load the user data into a proper object
    my $phab_user = Bugzilla::Extension::PhabBugz::User->new($user_data);

    if (!$phab_user->bugzilla_id) {
        WARN("SKIPPING: No bugzilla id associated with user");
        return;
    }

    my $bug_user  = $phab_user->bugzilla_user;

    # Pre setup before querying DB
    my $old_user = set_phab_user();

    # CHECK AND WARN FOR POSSIBLE USERNAME SQUATTING
    INFO("Checking for username squatters");
    my $dbh     = Bugzilla->dbh;
    my $regexp  = $dbh->quote( ":?:" . quotemeta($phab_user->name) . "[[:>:]]" );
    my $results = $dbh->selectall_arrayref( "
        SELECT userid, login_name, realname
          FROM profiles
         WHERE userid != ? AND " . $dbh->sql_regexp( 'realname', $regexp ),
        { Slice => {} },
        $bug_user->id );
    if (@$results) {
        # The email client will display the Date: header in the desired timezone,
        # so we can always use UTC here.
        my $timestamp = Bugzilla->dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
        $timestamp = format_time($timestamp, '%a, %d %b %Y %T %z', 'UTC');

        foreach my $row (@$results) {
            WARN(
                'Possible username squatter: ',
                'phab user login: ' . $phab_user->name,
                ' phab user realname: ' . $phab_user->realname,
                ' bugzilla user id: ' . $row->{userid},
                ' bugzilla login: ' . $row->{login_name},
                ' bugzilla realname: ' . $row->{realname}
            );

            my $vars = {
                date               => $timestamp,
                phab_user_login    => $phab_user->name,
                phab_user_realname => $phab_user->realname,
                bugzilla_userid    => $bug_user->id,
                bugzilla_login     => $bug_user->login,
                bugzilla_realname  => $bug_user->name,
                squat_userid       => $row->{userid},
                squat_login        => $row->{login_name},
                squat_realname     => $row->{realname}
            };

            my $message;
            my $template = Bugzilla->template;
            $template->process("admin/email/squatter-alert.txt.tmpl", $vars, \$message)
                || ThrowTemplateError($template->error());

            MessageToMTA($message);
        }
    }

    # ADD SUBSCRIBERS TO REVSISIONS FOR CURRENT PRIVATE BUGS

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

    INFO("Updating subscriber values for old private bugs");

    foreach my $bug_id (@bug_ids) {
        INFO("Processing bug $bug_id");

        my $bug = Bugzilla::Bug->new({ id => $bug_id, cache => 1 });

        my @attachments =
            grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

        foreach my $attachment (@attachments) {
            my ($revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);

            INFO("Processing revision D$revision_id");

            my $revision = Bugzilla::Extension::PhabBugz::Revision->new_from_query(
                { ids => [ int($revision_id) ] });

            $revision->add_subscriber($phab_user->phid);
            $revision->update();

            INFO("Revision $revision_id updated");
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
    TRACE(uc($type_full) . ": $last_id" );
    return $last_id;
}

sub save_last_id {
    my ( $self, $last_id, $type ) = @_;

    # Store the largest last key so we can start from there in the next session
    my $type_full = $type . "_last_id";
    TRACE("UPDATING " . uc($type_full) . ": $last_id" );
    Bugzilla->dbh->do( "REPLACE INTO phabbugz (name, value) VALUES (?, ?)",
        undef, $type_full, $last_id );
}

sub get_group_members {
    my ( $self, $group ) = @_;

    my $group_obj =
      ref $group ? $group : Bugzilla::Group->check( { name => $group, cache => 1 } );

    my $flat_list = join(',',
      @{ Bugzilla::Group->flatten_group_membership( $group_obj->id ) } );

    my $user_query = "
      SELECT DISTINCT profiles.userid
        FROM profiles, user_group_map AS ugm
       WHERE ugm.user_id = profiles.userid
             AND ugm.isbless = 0
             AND ugm.group_id IN($flat_list)";
    my $user_ids = Bugzilla->dbh->selectcol_arrayref($user_query);

    # Return matching users in Phabricator
    return Bugzilla::Extension::PhabBugz::User->match(
      {
        ids => $user_ids
      }
    );
}

1;
