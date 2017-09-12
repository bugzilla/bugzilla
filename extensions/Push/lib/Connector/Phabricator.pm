# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Phabricator;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::User;

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Util qw(
  add_comment_to_revision create_private_revision_policy
  edit_revision_policy get_attachment_revisions get_bug_role_phids
  get_revisions_by_ids intersect is_attachment_phab_revision
  make_revision_public make_revision_private set_revision_subscribers);
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util qw(is_public);

sub options {
    return (
        {
            name     => 'phabricator_url',
            label    => 'Phabricator URL',
            type     => 'string',
            default  => '',
            required => 1,
        }
    );
}

sub should_send {
    my ( $self, $message ) = @_;

    return 0 unless Bugzilla->params->{phabricator_enabled};

    # We are only interested currently in bug group, assignee, qa-contact, or cc changes.
    return 0
      unless $message->routing_key =~
      /^(?:attachment|bug)\.modify:.*\b(bug_group|assigned_to|qa_contact|cc)\b/;

    my $bug = $self->_get_bug_by_data( $message->payload_decoded ) || return 0;

    return $bug->has_attachment_with_mimetype(PHAB_CONTENT_TYPE);
}

sub send {
    my ( $self, $message ) = @_;

    my $logger = Bugzilla->push_ext->logger;

    my $data = $message->payload_decoded;

    my $bug = $self->_get_bug_by_data($data) || return PUSH_RESULT_OK;

    my $is_public = is_public($bug);

    my $phab_sync_groups = Bugzilla->params->{phabricator_sync_groups};
    ThrowUserError('invalid_phabricator_sync_groups') unless $phab_sync_groups;

    my $sync_group_names = [ split( '[,\s]+', $phab_sync_groups ) ];

    my $bug_groups = $bug->groups_in;
    my $bug_group_names = [ map { $_->name } @$bug_groups ];

    my @set_groups = intersect( $bug_group_names, $sync_group_names );

    my @revisions = get_attachment_revisions($bug);

    if ( !$is_public && !@set_groups ) {
        my $phab_error_message =
          'Revision is being made private due to unknown Bugzilla groups.';

        foreach my $revision (@revisions) {
            Bugzilla->audit(sprintf(
              'Making revision %s for bug %s private due to unkown Bugzilla groups: %s',
              $revision->{id},
              $bug->id,
              join(', ', @set_groups)
            ));
            add_comment_to_revision( $revision->{phid}, $phab_error_message );
            make_revision_private( $revision->{phid} );
        }

        my $num_revisions = 0 + @revisions;
        my $bmo_error_message =
          ( $num_revisions > 1
            ? 'Multiple revisions were'
            : 'One revision was' )
          . ' made private due to unknown Bugzilla groups.';

        my $user = Bugzilla::User->new( { name => PHAB_AUTOMATION_USER } );
        $user->{groups} = [ Bugzilla::Group->get_all ];
        $user->{bless_groups} = [ Bugzilla::Group->get_all ];
        Bugzilla->set_user($user);

        $bug->add_comment( $bmo_error_message, { isprivate => 0 } );

        my $bug_changes = $bug->update();
        $bug->send_changes($bug_changes);

        return PUSH_RESULT_OK;
    }

    my $group_change =
      ($message->routing_key =~ /^(?:attachment|bug)\.modify:.*\bbug_group\b/)
      ? 1
      : 0;

    my $subscribers;
    if ( !$is_public ) {
        $subscribers = get_bug_role_phids($bug);
    }

    foreach my $revision (@revisions) {
        my $revision_phid = $revision->{phid};

        if ( $is_public && $group_change ) {
            Bugzilla->audit(sprintf(
              'Making revision %s public for bug %s',
              $revision->{id},
              $bug->id
            ));
            make_revision_public($revision_phid);
        }
        elsif ( !$is_public && $group_change ) {
            Bugzilla->audit(sprintf(
              'Giving revision %s a custom policy for bug %s',
              $revision->{id},
              $bug->id
            ));
            my $policy_phid = create_private_revision_policy( $bug, \@set_groups );
            edit_revision_policy( $revision_phid, $policy_phid, $subscribers );
        }
        elsif ( !$is_public && !$group_change ) {
            Bugzilla->audit(sprintf(
              'Updating subscribers for %s for bug %s',
              $revision->{id},
              $bug->id
            ));
            set_revision_subscribers( $revision_phid, $subscribers );
        }
    }

    return PUSH_RESULT_OK;
}

sub _get_bug_by_data {
    my ( $self, $data ) = @_;
    my $bug_data = $self->_get_bug_data($data) || return 0;
    my $bug = Bugzilla::Bug->new( { id => $bug_data->{id} } );
}

sub _get_bug_data {
    my ( $self, $data ) = @_;
    my $target = $data->{event}->{target};
    if ( $target eq 'bug' ) {
        return $data->{bug};
    }
    elsif ( exists $data->{$target}->{bug} ) {
        return $data->{$target}->{bug};
    }
    else {
        return;
    }
}

1;
