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
  edit_revision_policy get_bug_role_phids get_revisions_by_ids
  intersect is_attachment_phab_revision make_revision_public
  make_revision_private);
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

    return 0
      unless $message->routing_key =~
      /^(?:attachment|bug)\.modify:.*\bbug_group\b/;

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

    if ( !$is_public && !@set_groups ) {
        my $phab_error_message =
          'Revision is being made private due to unknown Bugzilla groups.';

        my @revisions = $self->_get_attachment_revisions($bug);
        foreach my $revision (@revisions) {
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

    my $policy_phid;
    my $subscribers;
    if ( !$is_public ) {
        $policy_phid = create_private_revision_policy( $bug, \@set_groups );
        $subscribers = get_bug_role_phids($bug);
    }

    my @revisions = $self->_get_attachment_revisions($bug);
    foreach my $revision (@revisions) {
        my $revision_phid = $revision->{phid};

        if ($is_public) {
            make_revision_public($revision_phid);
        }
        else {
            edit_revision_policy( $revision_phid, $policy_phid, $subscribers );
        }
    }

    return PUSH_RESULT_OK;
}

sub _get_attachment_revisions() {
    my ( $self, $bug ) = @_;

    my @revisions;

    my @attachments =
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

    if (@attachments) {
        my @revision_ids;
        foreach my $attachment (@attachments) {
            my ($revision_id) =
              ( $attachment->filename =~ PHAB_ATTACHMENT_PATTERN );
            next if !$revision_id;
            push( @revision_ids, int($revision_id) );
        }

        if (@revision_ids) {
            @revisions = get_revisions_by_ids( \@revision_ids );
        }
    }

    return @revisions;
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
