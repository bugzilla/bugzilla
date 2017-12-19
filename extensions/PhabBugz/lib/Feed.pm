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
use Bugzilla::Extension::PhabBugz::Constants;
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
        my $skip = 0;
        my $story_id    = $story_data->{id};
        my $story_phid  = $story_data->{phid};
        my $author_phid = $story_data->{authorPHID};
        my $object_phid = $story_data->{objectPHID};
        my $story_text  = $story_data->{text};

        $self->logger->debug("STORY ID: $story_id");
        $self->logger->debug("STORY PHID: $story_phid");
        $self->logger->debug("AUTHOR PHID: $author_phid");
        $self->logger->debug("OBJECT PHID: $object_phid");
        $self->logger->debug("STORY TEXT: $story_text");

        # Only interested in changes to revisions for now.
        if ($object_phid !~ /^PHID-DREV/) {
            $self->logger->debug("SKIP: Not a revision change");
            $skip = 1;
        }

        # Skip changes done by phab-bot user
        my $phab_users = get_phab_bmo_ids({ phids => [$author_phid] });
        if (!$skip && @$phab_users) {
            my $user = Bugzilla::User->new({ id => $phab_users->[0]->{id}, cache => 1 });
            $skip = 1 if $user->login eq PHAB_AUTOMATION_USER;
        }

        if (!$skip) {
            my $revision = Bugzilla::Extension::PhabBugz::Revision->new({ phids => [$object_phid] });
            $self->process_revision_change($revision, $story_text);
        }
        else {
            $self->logger->info('SKIPPING');
        }

        # Store the largest last key so we can start from there in the next session
        $self->logger->debug("UPDATING FEED_LAST_ID: $story_id");
        $dbh->do("REPLACE INTO phabbugz (name, value) VALUES ('feed_last_id', ?)",
                 undef, $story_id);
    }
}

sub process_revision_change {
    my ($self, $revision, $story_text) = @_;

    # Pre setup before making changes
    my $old_user = set_phab_user();

    my $is_shadow_db = Bugzilla->is_shadow_db;
    Bugzilla->switch_to_main_db if $is_shadow_db;

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction;

    my ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");

    my $log_message = sprintf(
        "REVISION CHANGE FOUND: D%d: %s | bug: %d | %s",
        $revision->id,
        $revision->title,
        $revision->bug_id,
        $story_text);
    $self->logger->info($log_message);

    my $bug = Bugzilla::Bug->new({ id => $revision->bug_id, cache => 1 });

    # REVISION SECURITY POLICY

    # Do not set policy if a custom policy has already been set
    # This keeps from setting new custom policy everytime a change
    # is made.
    unless ($revision->view_policy =~ /^PHID-PLCY/) {

        # If bug is public then remove privacy policy
        if (!@{ $bug->groups_in }) {
            $revision->set_policy('view', 'public');
            $revision->set_policy('edit', 'users');
        }
        # else bug is private
        else {
            my @set_groups = get_security_sync_groups($bug);

            # If bug privacy groups do not have any matching synchronized groups,
            # then leave revision private and it will have be dealt with manually.
            if (!@set_groups) {
                add_security_sync_comments([$revision], $bug);
            }

            my $policy_phid = create_private_revision_policy($bug, \@set_groups);
            my $subscribers = get_bug_role_phids($bug);

            $revision->set_policy('view', $policy_phid);
            $revision->set_policy('edit', $policy_phid);
            $revision->set_subscribers($subscribers);
        }
    }

    my $attachment = create_revision_attachment($bug, $revision->id, $revision->title, $timestamp);

    # ATTACHMENT OBSOLETES

    # fixup attachments on current bug
    my @attachments =
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

    foreach my $attachment (@attachments) {
        my ($attach_revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
        next if $attach_revision_id != $revision->id;

        my $make_obsolete = $revision->status eq 'abandoned' ? 1 : 0;
        $attachment->set_is_obsolete($make_obsolete);

        if ($revision->id == $attach_revision_id
            && $revision->title ne $attachment->description) {
            $attachment->set_description($revision->title);
        }

        $attachment->update($timestamp);
        last;
    }

    # fixup attachments with same revision id but on different bugs
    my $other_attachments = Bugzilla::Attachment->match({
        mimetype => PHAB_CONTENT_TYPE,
        filename => 'phabricator-D' . $revision->id . '-url.txt',
        WHERE    => { 'bug_id != ? AND NOT isobsolete' => $bug->id }
    });
    foreach my $attachment (@$other_attachments) {
        $attachment->set_is_obsolete(1);
        $attachment->update($timestamp);
    }

    # REVIEWER STATUSES

    my (@accepted_phids, @denied_phids, @accepted_user_ids, @denied_user_ids);
    foreach my $reviewer (@{ $revision->reviewers }) {
        push(@accepted_phids, $reviewer->phab_phid) if $reviewer->phab_review_status eq 'accepted';
        push(@denied_phids, $reviewer->phab_phid) if $reviewer->phab_review_status eq 'rejected';
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
            $flag_type = $flag->type;
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

        $flag_type ||= first { $_->name eq 'review' } @{ $attachment->flag_types };

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

    Bugzilla::BugMail::Send($revision->bug_id, { changer => Bugzilla->user });

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
