# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Feed;

use 5.10.1;

use List::Util qw(first);
use List::MoreUtils qw(any);
use Moo;

use Bugzilla::Constants;
use Bugzilla::Util qw(diff_arrays);

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Policy;
use Bugzilla::Extension::PhabBugz::Revision;
use Bugzilla::Extension::PhabBugz::Util qw(
    add_security_sync_comments
    create_private_revision_policy
    create_revision_attachment
    edit_revision_policy
    get_bug_role_phids
    get_phab_bmo_ids
    get_security_sync_groups
    is_attachment_phab_revision
    make_revision_public
    request
    set_phab_user
);

has 'is_daemon' => ( is => 'rw', default => 0 );
has 'logger'    => ( is => 'rw' );

sub start {
    my ($self) = @_;
    while (1) {
        my $ok = eval {
            if (Bugzilla->params->{phabricator_enabled}) {
                $self->feed_query();
                Bugzilla->_cleanup();
            }
            1;
        };
        $self->logger->error( $@ // "unknown exception" ) unless $ok;
        sleep(PHAB_POLL_SECONDS);
    }
}

sub feed_query {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    # Ensure Phabricator syncing is enabled
    if (!Bugzilla->params->{phabricator_enabled}) {
        $self->logger->info("PHABRICATOR SYNC DISABLED");
        return;
    }

    $self->logger->info("FEED: Fetching new transactions");

    my $last_id = $dbh->selectrow_array("
        SELECT value FROM phabbugz WHERE name = 'feed_last_id'");
    $last_id ||= 0;
    $self->logger->debug("QUERY LAST_ID: $last_id");

    # Check for new transctions (stories)
    my $transactions = $self->feed_transactions($last_id);
    if (!@$transactions) {
        $self->logger->info("FEED: No new transactions");
        return;
    }

    # Process each story
    foreach my $story_data (@$transactions) {
        my $story_id    = $story_data->{id};
        my $story_phid  = $story_data->{phid};
        my $author_phid = $story_data->{authorPHID};
        my $object_phid = $story_data->{objectPHID};
        my $story_text  = $story_data->{text};

        $self->logger->debug("STORY ID: $story_id");
        $self->logger->debug("STORY PHID: $story_phid");
        $self->logger->debug("AUTHOR PHID: $author_phid");
        $self->logger->debug("OBJECT PHID: $object_phid");
        $self->logger->info("STORY TEXT: $story_text");

        # Only interested in changes to revisions for now.
        if ($object_phid !~ /^PHID-DREV/) {
            $self->logger->debug("SKIPPING: Not a revision change");
            $self->save_feed_last_id($story_id);
            next;
        }

        # Skip changes done by phab-bot user
        my $phab_users = get_phab_bmo_ids({ phids => [$author_phid] });
        if (@$phab_users) {
            my $user = Bugzilla::User->new({ id => $phab_users->[0]->{id}, cache => 1 });
            if ($user->login eq PHAB_AUTOMATION_USER) {
                $self->logger->debug("SKIPPING: Change made by phabricator user");
                $self->save_feed_last_id($story_id);
                next;
            }
        }

        $self->process_revision_change($object_phid, $story_text);
        $self->save_feed_last_id($story_id);
    }
}

sub save_feed_last_id {
    my ($self, $story_id) = @_;
    # Store the largest last key so we can start from there in the next session
    $self->logger->debug("UPDATING FEED_LAST_ID: $story_id");
    Bugzilla->dbh->do("REPLACE INTO phabbugz (name, value) VALUES ('feed_last_id', ?)",
                      undef, $story_id);
}

sub process_revision_change {
    my ($self, $revision_phid, $story_text) = @_;

    # Load the revision from Phabricator
    my $revision = Bugzilla::Extension::PhabBugz::Revision->new({ phids => [ $revision_phid ] });

    # NO BUG ID

    if (!$revision->bug_id) {
        if ($story_text =~ /\s+created\s+D\d+/) {
            # If new revision and bug id was omitted, make revision public
            $self->logger->debug("No bug associated with new revision. Marking public.");
            $revision->set_policy('view', 'public');
            $revision->set_policy('edit', 'users');
            $revision->update();
            $self->logger->info("SUCCESS");
            return;
        }
        else {
            $self->logger->debug("SKIPPING: No bug associated with revision change");
            return;
        }
    }

    my $log_message = sprintf(
        "REVISION CHANGE FOUND: D%d: %s | bug: %d | %s",
        $revision->id,
        $revision->title,
        $revision->bug_id,
        $story_text);
    $self->logger->info($log_message);

    # Pre setup before making changes
    my $old_user = set_phab_user();

    my $is_shadow_db = Bugzilla->is_shadow_db;
    Bugzilla->switch_to_main_db if $is_shadow_db;

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction;

    my $bug = Bugzilla::Bug->new({ id => $revision->bug_id, cache => 1 });

    # REVISION SECURITY POLICY

    # If bug is public then remove privacy policy
    if (!@{ $bug->groups_in }) {
        $self->logger->debug('Bug is public so setting view/edit public');
        $revision->set_policy('view', 'public');
        $revision->set_policy('edit', 'users');
    }
    # else bug is private.
    else {
        my @set_groups = get_security_sync_groups($bug);

        # If bug privacy groups do not have any matching synchronized groups,
        # then leave revision private and it will have be dealt with manually.
        if (!@set_groups) {
            $self->logger->debug('No matching groups. Adding comments to bug and revision');
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
                $self->logger->debug("Loading current policy: " . $revision->view_policy);
                $current_policy
                    = Bugzilla::Extension::PhabBugz::Policy->new_from_query({ phids => [ $revision->view_policy ]});
                my $current_projects = $current_policy->rule_projects;
                $self->logger->debug("Current policy projects: " . join(", ", @$current_projects));
                my ($added, $removed) = diff_arrays($current_projects, \@set_projects);
                if (@$added || @$removed) {
                    $self->logger->debug('Project groups do not match. Need new custom policy');
                    $current_policy= undef;
                }
                else {
                    $self->logger->debug('Project groups match. Leaving current policy as-is');
                }
            }

            if (!$current_policy) {
                $self->logger->debug("Creating new custom policy: " . join(", ", @set_projects));
                my $new_policy = Bugzilla::Extension::PhabBugz::Policy->create(\@set_projects);
                $revision->set_policy('view', $new_policy->phid);
                $revision->set_policy('edit', $new_policy->phid);
            }

            my $subscribers = get_bug_role_phids($bug);
            $revision->set_subscribers($subscribers);
        }
    }

    my ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");

    my $attachment = create_revision_attachment($bug, $revision->id, $revision->title, $timestamp);

    # ATTACHMENT OBSOLETES

    # fixup attachments on current bug
    my @attachments =
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

    foreach my $attachment (@attachments) {
        my ($attach_revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
        next if $attach_revision_id != $revision->id;

        my $make_obsolete = $revision->status eq 'abandoned' ? 1 : 0;
        $self->logger->debug('Updating obsolete status on attachmment ' . $attachment->id);
        $attachment->set_is_obsolete($make_obsolete);

        if ($revision->title ne $attachment->description) {
            $self->logger->debug('Updating description on attachment ' . $attachment->id);
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
        $self->logger->debug('Updating obsolete status on attachment ' .
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
            $comment .= $flag_data->{setter}->name . " has been removed from the revision.\n";
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

    $dbh->bz_commit_transaction;
    Bugzilla->switch_to_shadow_db if $is_shadow_db;

    Bugzilla->set_user($old_user);

    $self->logger->info("SUCCESS");
}

sub feed_transactions {
    my ($self, $after) = @_;
    my $data = { view => 'text' };
    $data->{after} = $after if $after;
    my $result = request('feed.query_id', $data);
    unless (ref $result->{result}{data} eq 'ARRAY'
            && @{ $result->{result}{data} })
    {
        return [];
    }
    # Guarantee that the data is in ascending ID order
    return [ sort { $a->{id} <=> $b->{id} } @{ $result->{result}{data} } ];
}

1;
