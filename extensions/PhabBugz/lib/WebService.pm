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

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::User;
use Bugzilla::Util qw(detaint_natural trick_taint);
use Bugzilla::WebService::Constants;
use Types::Standard qw(-types slurpy);
use Type::Params qw(compile);

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Revision;
use Bugzilla::Extension::PhabBugz::Util qw(request);

use MIME::Base64 qw(decode_base64);
use Try::Tiny;

use constant READ_ONLY => qw(
    bug_revisions
    check_user_enter_bug_permission
    check_user_permission_for_bug
);

use constant PUBLIC_METHODS => qw(
    bug_revisions
    check_user_enter_bug_permission
    check_user_permission_for_bug
    set_build_target
);

sub _check_phabricator {
    # Ensure PhabBugz is on
    ThrowUserError('phabricator_not_enabled')
        unless Bugzilla->params->{phabricator_enabled};
}

sub _validate_phab_user {
    my ($self, $user) = @_;

    $self->_check_phabricator();

    # Validate that the requesting user's email matches phab-bot
    ThrowUserError('phabricator_unauthorized_user')
        unless $user->login eq PHAB_AUTOMATION_USER;
}

sub check_user_permission_for_bug {
    my ($self, $params) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    $self->_validate_phab_user($user);

    # Validate that a bug id and user id are provided
    ThrowUserError('phabricator_invalid_request_params')
        unless ($params->{bug_id} && $params->{user_id});

    # Validate that the user exists
    my $target_user = Bugzilla::User->check({ id => $params->{user_id}, cache => 1 });

    # Send back an object which says { "result": 1|0 }
    return {
        result => $target_user->can_see_bug($params->{bug_id})
    };
}

sub check_user_enter_bug_permission {
    my ($self, $params) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    $self->_validate_phab_user($user);

    # Validate that a product name and user id are provided
    ThrowUserError('phabricator_invalid_request_params')
        unless ($params->{product} && $params->{user_id});

    # Validate that the user exists
    my $target_user = Bugzilla::User->check({ id => $params->{user_id}, cache => 1 });

    # Send back an object with the attribute "result" set to 1 if the user
    # can enter bugs into the given product, or 0 if not.
    return {
        result => $target_user->can_enter_product($params->{product}) ? 1 : 0
    };
}

sub set_build_target {
    my ( $self, $params ) = @_;

    # Phabricator only supports sending credentials via HTTP Basic Auth
    # so we exploit that function to pass in an API key as the password
    # of basic auth. BMO does not support basic auth but does support
    # use of API keys.
    my $http_auth = Bugzilla->cgi->http('Authorization');
    $http_auth =~ s/^Basic\s+//;
    $http_auth = decode_base64($http_auth);
    my ($login, $api_key) = split(':', $http_auth);
    $params->{'Bugzilla_login'}   = $login;
    $params->{'Bugzilla_api_key'} = $api_key;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    $self->_validate_phab_user($user);

    my $revision_id  = $params->{revision_id};
    my $build_target = $params->{build_target};

    ThrowUserError('invalid_phabricator_revision_id')
      unless detaint_natural($revision_id);

    ThrowUserError('invalid_phabricator_build_target')
      unless $build_target =~ /^PHID-HMBT-[a-zA-Z0-9]+$/;
    trick_taint($build_target);

    Bugzilla->dbh->do(
        'INSERT INTO phabbugz (name, value) VALUES (?, ?)',
        undef,
        'build_target_' . $revision_id,
        $build_target
    );

    return { result => 1 };
}

sub bug_revisions {
    state $check = compile(Object, Dict[bug_id => Int]);
    my ( $self, $params ) = $check->(@_);

    $self->_check_phabricator();

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    # Validate that a bug id and user id are provided
    ThrowUserError('phabricator_invalid_request_params')
        unless $params->{bug_id};

    # Validate that the user can see the bug itself
    my $bug = Bugzilla::Bug->check( { id => $params->{bug_id}, cache => 1 } );

    my @revision_ids;
    foreach my $attachment ( @{ $bug->attachments } ) {
        next if $attachment->contenttype ne PHAB_CONTENT_TYPE;
        my ($revision_id) = ( $attachment->filename =~ PHAB_ATTACHMENT_PATTERN );
        next if !$revision_id;
        push @revision_ids, int $revision_id;
    }

    my $response = request(
        'differential.revision.search',
        {
            attachments => {
                'projects'        => 1,
                'reviewers'       => 1,
                'subscribers'     => 1,
                'reviewers-extra' => 1,
            },
            constraints => {
                ids => \@revision_ids,
            },
            order => 'newest',
        }
    );

    state $SearchResult = Dict[
        result => Dict[
            # HashRef below could be better,
            # but ::Revision takes a lot of options.
            data => ArrayRef[ HashRef ],
            slurpy Any,
        ],
        slurpy Any,
    ];

    my $error = $SearchResult->validate($response);
    ThrowCodeError( 'phabricator_api_error', { reason => $error } )
        if defined $error;

    my $revision_status_map = {
        'abandoned'       => 'Abandoned',
        'accepted'        => 'Accepted',
        'changes-planned' => 'Changes Planned',
        'needs-review'    => 'Needs Review',
        'needs-revision'  => 'Needs Revision',
    };

    my $review_status_map = {
        'accepted'       => 'Accepted',
        'accepted-prior' => 'Accepted Prior Diff',
        'added'          => 'Review Requested',
        'blocking'       => 'Blocking Review',
        'rejected'       => 'Requested Changes',
        'resigned'       => 'Resigned'
    };

    my @revisions;
    foreach my $revision ( @{ $response->{result}{data} } ) {
        my $revision_obj = Bugzilla::Extension::PhabBugz::Revision->new($revision);
        my $revision_data = {
            id     => 'D' . $revision_obj->id,
            author => $revision_obj->author->name,
            status => $revision_obj->status,
            long_status => $revision_status_map->{$revision_obj->status} || $revision_obj->status
        };

        my @reviews;
        foreach my $review ( @{ $revision_obj->reviews } ) {
            push @reviews, {
                user        => $review->{user}->name,
                status      => $review->{status},
                long_status => $review_status_map->{$review->{status}} || $review->{status}
            };
        }
        $revision_data->{reviews} = \@reviews;

        if ( $revision_obj->view_policy ne 'public' ) {
            $revision_data->{title} = '(secured)';
        }
        else {
            $revision_data->{title} = $revision_obj->title;
        }

        push @revisions, $revision_data;
    }

    # sort by revision id
    @revisions = sort { $a->{id} cmp $b->{id} } @revisions;

    return { revisions => \@revisions };
}

sub rest_resources {
    return [
        # Set build target in Phabricator
        qr{^/phabbugz/build_target/(\d+)/(PHID-HMBT-.*)$}, {
            POST => {
                method => 'set_build_target',
                params => sub {
                    return {
                        revision_id  => $_[0],
                        build_target => $_[1]
                    };
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
        qr{^/phabbugz/check_enter_bug/([^/]+)/(\d+)$}, {
            GET => {
                method => 'check_user_enter_bug_permission',
                params => sub {
                    return { product => $_[0], user_id => $_[1] };
                },
            },
        },
        qr{^/phabbugz/bug_revisions/(\d+)$}, {
            GET => {
                method => 'bug_revisions',
                params => sub {
                    return { bug_id => $_[0] };
                },
            },
        },
    ];
}

1;
