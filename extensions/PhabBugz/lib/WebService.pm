# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::BugMail;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::Push::Util qw(is_public);
use Bugzilla::User;
use Bugzilla::Util qw(correct_urlbase detaint_natural);
use Bugzilla::WebService::Constants;

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Util qw(
    create_revision_attachment
    create_private_revision_policy
    edit_revision_policy
    get_bug_role_phids
    get_project_phid
    get_revisions_by_ids
    intersect
    is_attachment_phab_revision
    make_revision_public
    request
);

use List::Util qw(first);
use List::MoreUtils qw(any);
use MIME::Base64 qw(decode_base64);

use constant PUBLIC_METHODS => qw(
    check_user_permission_for_bug
    obsolete_attachments
    revision
    update_reviewer_statuses
);

sub revision {
    my ($self, $params) = @_;

    # Phabricator only supports sending credentials via HTTP Basic Auth
    # so we exploit that function to pass in an API key as the password
    # of basic auth. BMO does not support basic auth but does support
    # use of API keys.
    my $http_auth = Bugzilla->cgi->http('Authorization');
    $http_auth =~ s/^Basic\s+//;
    $http_auth = decode_base64($http_auth);
    my ($login, $api_key) = split(':', $http_auth);
    $params->{'Bugzilla_login'} = $login;
    $params->{'Bugzilla_api_key'} = $api_key;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    # Prechecks
    _phabricator_precheck($user);

    unless (defined $params->{revision} && detaint_natural($params->{revision})) {
        ThrowCodeError('param_required', { param => 'revision' })
    }

    # Obtain more information about the revision from Phabricator
    my $revision_id = $params->{revision};
    my @revisions = get_revisions_by_ids([$revision_id]);
    my $revision = $revisions[0];

    my $revision_phid  = $revision->{phid};
    my $revision_title = $revision->{fields}{title} || 'Unknown Description';
    my $bug_id         = $revision->{fields}{'bugzilla.bug-id'};

    my $bug = Bugzilla::Bug->check($bug_id);

    # If bug is public then remove privacy policy
    my $result;
    if (is_public($bug)) {
        $result = make_revision_public($revision_id);
    }
    # else bug is private
    else {
        my $phab_sync_groups = Bugzilla->params->{phabricator_sync_groups}
            || ThrowUserError('invalid_phabricator_sync_groups');
        my $sync_group_names = [ split('[,\s]+', $phab_sync_groups) ];

        my $bug_groups = $bug->groups_in;
        my $bug_group_names = [ map { $_->name } @$bug_groups ];

        my @set_groups = intersect($bug_group_names, $sync_group_names);

        # If bug privacy groups do not have any matching synchronized groups,
        # then leave revision private and it will have be dealt with manually.
        if (!@set_groups) {
            ThrowUserError('invalid_phabricator_sync_groups');
        }

        my $policy_phid = create_private_revision_policy($bug, \@set_groups);
        my $subscribers = get_bug_role_phids($bug);
        $result = edit_revision_policy($revision_phid, $policy_phid, $subscribers);
    }

    my $attachment = create_revision_attachment($bug, $revision_id, $revision_title);

    Bugzilla::BugMail::Send($bug_id, { changer => $user });

    return {
        result          => $result,
        attachment_id   => $attachment->id,
        attachment_link => correct_urlbase() . "attachment.cgi?id=" . $attachment->id
    };
}

sub check_user_permission_for_bug {
    my ($self, $params) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    # Prechecks
    _phabricator_precheck($user);

    # Validate that a bug id and user id are provided
    ThrowUserError('phabricator_invalid_request_params')
        unless ($params->{bug_id} && $params->{user_id});

    # Validate that the user and bug exist
    my $target_user = Bugzilla::User->check({ id => $params->{user_id}, cache => 1 });

    # Send back an object which says { "result": 1|0 }
    return {
        result => $target_user->can_see_bug($params->{bug_id})
    };
}

sub update_reviewer_statuses {
    my ($self, $params) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    # Prechecks
    _phabricator_precheck($user);

    my $revision_id = $params->{revision_id};
    unless (defined $revision_id && detaint_natural($revision_id)) {
        ThrowCodeError('param_required', { param => 'revision_id' })
    }

    my $bug_id = $params->{bug_id};
    unless (defined $bug_id && detaint_natural($bug_id)) {
        ThrowCodeError('param_required', { param => 'bug_id' })
    }

    my $accepted_user_ids = $params->{accepted_users};
    defined $accepted_user_ids
      || ThrowCodeError('param_required', { param => 'accepted_users' });
    $accepted_user_ids = [ split(':', $accepted_user_ids) ];

    my $bug = Bugzilla::Bug->check($bug_id);

    my @attachments =
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

    return { result => [] } if !@attachments;

    my $dbh = Bugzilla->dbh;
    my ($timestamp) = $dbh->selectrow_array("SELECT NOW()");

    my @updated_attach_ids;
    foreach my $attachment (@attachments) {
        my ($curr_revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
        next if $revision_id != $curr_revision_id;

        # Clear old flags if no longer accepted or a previous
        # acceptor is not in the new list.
        my (@old_flags, @new_flags, %accepted_done, $flag_type);
        foreach my $flag (@{ $attachment->flags }) {
            next if $flag->type->name ne 'review';
            $flag_type = $flag->type;
            unless (any { $flag->setter->id == $_ } @$accepted_user_ids) {
                push(@old_flags, { id => $flag->id, status => 'X' });
            }
            else {
                $accepted_done{$flag->setter->id}++; # so we do not set it again as new
            }
        }

        $flag_type ||= first { $_->name eq 'review' } @{ $attachment->flag_types };

        # Create new flags
        foreach my $user_id (@$accepted_user_ids) {
            next if $accepted_done{$user_id};
            my $user = Bugzilla::User->check({ id => $user_id, cache => 1 });
            push(@new_flags, { type_id => $flag_type->id, setter => $user, status => '+' });
        }

        $attachment->set_flags(\@old_flags, \@new_flags);
        $attachment->update($timestamp);

        push(@updated_attach_ids, $attachment->id);
    }

    Bugzilla::BugMail::Send($bug_id, { changer => $user }) if @updated_attach_ids;

    return { result => \@updated_attach_ids };
}

sub obsolete_attachments {
    my ($self, $params) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    # Prechecks
    _phabricator_precheck($user);

    my $revision_id = $params->{revision_id};
    unless (defined $revision_id && detaint_natural($revision_id)) {
        ThrowCodeError('param_required', { param => 'revision' })
    }

    my $bug_id= $params->{bug_id};
    unless (defined $bug_id && detaint_natural($bug_id)) {
        ThrowCodeError('param_required', { param => 'bug_id' })
    }

    my $make_obsolete = $params->{make_obsolete};
    unless (defined $make_obsolete) {
        ThrowCodeError('param_required', { param => 'make_obsolete' })
    }
    $make_obsolete = $make_obsolete ? 1 : 0;

    my $bug = Bugzilla::Bug->check($bug_id);

    my @attachments =
      grep { is_attachment_phab_revision($_, 1) } @{ $bug->attachments() };

    return { result => [] } if !@attachments;

    my $dbh = Bugzilla->dbh;
    my ($timestamp) = $dbh->selectrow_array("SELECT NOW()");

    my @updated_attach_ids;
    foreach my $attachment (@attachments) {
        my ($curr_revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
        next if $revision_id != $curr_revision_id;

        $attachment->set_is_obsolete($make_obsolete);
        $attachment->update($timestamp);

        push(@updated_attach_ids, $attachment->id);
    }

    Bugzilla::BugMail::Send($bug_id, { changer => $user }) if @updated_attach_ids;

    return { result => \@updated_attach_ids };
}

sub _phabricator_precheck {
    my ($user) = @_;

    # Ensure PhabBugz is on
    ThrowUserError('phabricator_not_enabled')
        unless Bugzilla->params->{phabricator_enabled};

    # Validate that the requesting user's email matches phab-bot
    ThrowUserError('phabricator_unauthorized_user')
        unless $user->login eq PHAB_AUTOMATION_USER;
}

sub rest_resources {
    return [
        # Revision creation
        qr{^/phabbugz/revision/([^/]+)$}, {
            POST => {
                method => 'revision',
                params => sub {
                    return { revision => $_[0] };
                }
            }
        },
        # Bug permission checks
        qr{^/phabbugz/check_bug/(\d+)/(\d+)$}, {
            GET => {
                method => 'check_user_permission_for_bug',
                params => sub {
                    return { bug_id => $_[0], user_id => $_[1] };
                }
            }
        },
        # Update reviewer statuses
        qr{^/phabbugz/update_reviewer_statuses$}, {
            PUT => {
                method => 'update_reviewer_statuses',
            }
        },
        # Obsolete attachments
        qr{^/phabbugz/obsolete$}, {
            PUT => {
                method => 'obsolete_attachments',
            }
        }
    ];
}

1;
