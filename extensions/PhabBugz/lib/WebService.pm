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

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Util qw(detaint_natural trick_taint);
use Bugzilla::WebService::Constants;

use Bugzilla::Extension::PhabBugz::Constants;

use List::Util qw(first);
use List::MoreUtils qw(any);
use MIME::Base64 qw(decode_base64);

use constant READ_ONLY => qw(
    check_user_enter_bug_permission
    check_user_permission_for_bug
);

use constant PUBLIC_METHODS => qw(
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
        "INSERT INTO phabbugz (name, value) VALUES (?, ?)",
        undef,
        'build_target_' . $revision_id,
        $build_target
    );

    return { result => 1 };
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
    ];
}

1;
