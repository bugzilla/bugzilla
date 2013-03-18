# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Persona::Login;
use strict;
use base qw(Bugzilla::Auth::Login);

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Token;

use JSON;
use LWP::UserAgent;

use constant requires_verification   => 0;
use constant is_automatic            => 1;
use constant user_can_create_account => 1;

sub get_login_info {
    my ($self) = @_;

    my $cgi = Bugzilla->cgi;

    my $assertion = $cgi->param("persona_assertion");
    # Avoid the assertion being copied into any 'echoes' of the current URL
    # in the page.
    $cgi->delete('persona_assertion');

    if (!$assertion || !Bugzilla->params->{persona_verify_url}) {
        return { failure => AUTH_NODATA };
    }

    my $token = $cgi->param("token");
    $cgi->delete('token');
    check_hash_token($token, ['login']);

    my $urlbase = new URI(correct_urlbase());
    my $audience = $urlbase->scheme . "://" . $urlbase->host_port;

    my $ua = new LWP::UserAgent( timeout => 10 );

    my $response = $ua->post(Bugzilla->params->{persona_verify_url},
                             [ assertion => $assertion,
                               audience  => $audience ]);
    if ($response->is_error) {
        return { failure    => AUTH_ERROR,
                 user_error => 'persona_server_fail',
                 details    => { reason => $response->message }};
    }

    my $info;
    eval {
        $info = decode_json($response->decoded_content());
    };
    if ($@) {
        return { failure    => AUTH_ERROR,
                 user_error => 'persona_server_fail',
                 details    => { reason => 'Received a malformed response.' }};
    }
    if ($info->{'status'} eq 'failure') {
        return { failure    => AUTH_ERROR,
                 user_error => 'persona_server_fail',
                 details    => { reason => $info->{reason} }};
    }

    if ($info->{'status'} eq "okay" &&
        $info->{'audience'} eq $audience &&
        ($info->{'expires'} / 1000) > time())
    {
        my $login_data = {
            'username' => $info->{'email'}
        };

        my $result = Bugzilla::Auth::Verify->create_or_update_user($login_data);
        return $result if $result->{'failure'};

        my $user = $result->{'user'};

        # You can restrict people in a particular group from logging in using
        # Persona by making that group a member of a group called
        # "no-browser-id".
        #
        # If you have your "createemailregexp" set up in such a way that a
        # newly-created account is a member of "no-browser-id", this code will
        # create an account for them and then fail their login. Which isn't
        # great, but they can still use normal-Bugzilla-login password
        # recovery.
        if ($user->in_group('no-browser-id')) {
            return { failure    => AUTH_ERROR,
                     user_error => 'persona_account_too_powerful' };
        }

        $login_data->{'user'} = $user;
        $login_data->{'user_id'} = $user->id;

        return $login_data;
    }
    else {
        return { failure => AUTH_LOGINFAILED };
    }
}

# Pinched from Bugzilla::Auth::Login::CGI
sub fail_nodata {
    my ($self) = @_;
    my $cgi = Bugzilla->cgi;
    my $template = Bugzilla->template;

    if (Bugzilla->usage_mode != USAGE_MODE_BROWSER) {
        ThrowUserError('login_required');
    }

    print $cgi->header();
    $template->process("account/auth/login.html.tmpl", { 'target' => $cgi->url(-relative=>1) })
        || ThrowTemplateError($template->error());
    exit;
}

1;
