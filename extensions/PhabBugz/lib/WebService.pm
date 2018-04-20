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
use Bugzilla::Util qw(detaint_natural datetime_from time_ago);
use Bugzilla::WebService::Constants;

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Util qw(
    add_security_sync_comments
    create_private_revision_policy
    create_revision_attachment
    edit_revision_policy
    get_bug_role_phids
    get_phab_bmo_ids
    get_needs_review
    get_project_phid
    get_revisions_by_ids
    get_security_sync_groups
    intersect
    is_attachment_phab_revision
    make_revision_public
    request
);

use DateTime ();
use List::Util qw(first uniq);
use List::MoreUtils qw(any);
use MIME::Base64 qw(decode_base64);

use constant READ_ONLY => qw(
    needs_review
);

use constant PUBLIC_METHODS => qw(
    check_user_permission_for_bug
    obsolete_attachments
    revision
    update_reviewer_statuses
    needs_review
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
    my $revisions = get_revisions_by_ids([$revision_id]);
    my $revision = $revisions->[0];

    my $revision_phid  = $revision->{phid};
    my $revision_title = $revision->{fields}{title} || 'Unknown Description';
    my $bug_id         = $revision->{fields}{'bugzilla.bug-id'};

    my $bug = Bugzilla::Bug->new($bug_id);

    # If bug is public then remove privacy policy
    my $result;
    if (is_public($bug)) {
        $result = make_revision_public($revision_id);
    }
    # else bug is private
    else {
        my @set_groups = get_security_sync_groups($bug);

        # If bug privacy groups do not have any matching synchronized groups,
        # then leave revision private and it will have be dealt with manually.
        if (!@set_groups) {
            add_security_sync_comments($revisions, $bug);
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
        attachment_link => Bugzilla->localconfig->{urlbase} . "attachment.cgi?id=" . $attachment->id
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

    my $denied_user_ids = $params->{denied_users};
    defined $denied_user_ids
      || ThrowCodeError('param_required', { param => 'denied_users' });
    $denied_user_ids = [ split(':', $denied_user_ids) ];

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

        # Clear old flags if no longer accepted
        my (@denied_flags, @new_flags, @removed_flags, %accepted_done, $flag_type);
        foreach my $flag (@{ $attachment->flags }) {
            next if $flag->type->name ne 'review';
            $flag_type = $flag->type if $flag->type->is_active;
            if (any { $flag->setter->id == $_ } @$denied_user_ids) {
                push(@denied_flags, { id => $flag->id, setter => $flag->setter, status => 'X' });
            }
            if (any { $flag->setter->id == $_ } @$accepted_user_ids) {
                $accepted_done{$flag->setter->id}++;
            }
            if ($flag->status eq '+'
                && !any { $flag->setter->id == $_ } (@$accepted_user_ids, @$denied_user_ids)) {
                push(@removed_flags, { id => $flag->id, setter => $flag->setter, status => 'X' });
            }
        }

        $flag_type ||= first { $_->name eq 'review' && $_->is_active } @{ $attachment->flag_types };

        # Create new flags
        foreach my $user_id (@$accepted_user_ids) {
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
            $comment .= "\n" . Bugzilla->params->{phabricator_base_uri} . "D" . $revision_id;
            # Add transaction_id as anchor if one present
            $comment .= "#" . $params->{transaction_id} if $params->{transaction_id};
            $bug->add_comment($comment, {
                isprivate  => $attachment->isprivate,
                type       => CMT_ATTACHMENT_UPDATED,
                extra_data => $attachment->id
            });
        }

        $attachment->set_flags([ @denied_flags, @removed_flags ], \@new_flags);
        $attachment->update($timestamp);
        $bug->update($timestamp) if $comment;

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
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

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

sub needs_review {
    my ($self, $params) = @_;
    ThrowUserError('phabricator_not_enabled')
        unless Bugzilla->params->{phabricator_enabled};
    my $user = Bugzilla->login(LOGIN_REQUIRED);
    my $dbh  = Bugzilla->dbh;

    my $reviews = get_needs_review();

    # map author phids to bugzilla users
    my $author_id_map = get_phab_bmo_ids({
        phids => [
            uniq
            grep { defined }
            map { $_->{fields}{authorPHID} }
            @$reviews
        ]
    });
    my %author_phab_to_id = map { $_->{phid} => $_->{id} } @$author_id_map;
    my $author_users      = Bugzilla::User->new_from_list([ map { $_->{id} } @$author_id_map ]);
    my %author_id_to_user = map { $_->id => $_ } @$author_users;

    # bug data
    my $visible_bugs = $user->visible_bugs([
        uniq
        grep { $_ }
        map { $_->{fields}{'bugzilla.bug-id'} }
        @$reviews
    ]);

    # get all bug statuses and summaries in a single query to avoid creation of
    # many bug objects
    my %bugs;
    if (@$visible_bugs) {
        #<<<
        my $bug_rows =$dbh->selectall_arrayref(
            'SELECT bug_id, bug_status, short_desc ' .
            '  FROM bugs ' .
            ' WHERE bug_id IN (' . join(',', ('?') x @$visible_bugs) . ')',
            { Slice => {} },
            @$visible_bugs
        );
        #>>>
        %bugs = map { $_->{bug_id} => $_ } @$bug_rows;
    }

    # build result
    my $datetime_now = DateTime->now(time_zone => $user->timezone);
    my @result;
    foreach my $review (@$reviews) {
        my $review_flat = {
            id     => $review->{id},
            status => $review->{fields}{review_status},
            title  => $review->{fields}{title},
            url    => Bugzilla->params->{phabricator_base_uri} . 'D' . $review->{id},
        };

        # show date in user's timezone
        my $datetime = DateTime->from_epoch(
            epoch     => $review->{fields}{dateModified},
            time_zone => 'UTC'
        );
        $datetime->set_time_zone($user->timezone);
        $review_flat->{updated}       = $datetime->strftime('%Y-%m-%d %T %Z');
        $review_flat->{updated_fancy} = time_ago($datetime, $datetime_now);

        # review requester
        if (my $author = $author_id_to_user{$author_phab_to_id{ $review->{fields}{authorPHID} }}) {
            $review_flat->{author_name}  = $author->name;
            $review_flat->{author_email} = $author->email;
        }
        else {
            $review_flat->{author_name}  = 'anonymous';
            $review_flat->{author_email} = 'anonymous';
        }

        # referenced bug
        if (my $bug_id = $review->{fields}{'bugzilla.bug-id'}) {
            my $bug = $bugs{$bug_id};
            $review_flat->{bug_id}      = $bug_id;
            $review_flat->{bug_status}  = $bug->{bug_status};
            $review_flat->{bug_summary} = $bug->{short_desc};
        }

        push @result, $review_flat;
    }

    return { result => \@result };
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
        },
        # Review requests
        qw{^/phabbugz/needs_review$}, {
            GET => {
                method => 'needs_review',
            },
        },
    ];
}

1;
