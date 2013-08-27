# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Auth::Login::Cookie;

use 5.10.1;
use strict;

use parent qw(Bugzilla::Auth::Login);

use Bugzilla::Constants;
use Bugzilla::Util;

use List::Util qw(first);

use constant requires_persistence  => 0;
use constant requires_verification => 0;
use constant can_login => 0;

sub is_automatic { return $_[0]->login_token ? 0 : 1; }

# Note that Cookie never consults the Verifier, it always assumes
# it has a valid DB account or it fails.
sub get_login_info {
    my ($self) = @_;
    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;
    my ($user_id, $login_cookie);

    if (!Bugzilla->request_cache->{auth_no_automatic_login}) {
        $login_cookie = $cgi->cookie("Bugzilla_logincookie");
        $user_id      = $cgi->cookie("Bugzilla_login");

        # If cookies cannot be found, this could mean that they haven't
        # been made available yet. In this case, look at Bugzilla_cookie_list.
        unless ($login_cookie) {
            my $cookie = first {$_->name eq 'Bugzilla_logincookie'}
                                @{$cgi->{'Bugzilla_cookie_list'}};
            $login_cookie = $cookie->value if $cookie;
        }
        unless ($user_id) {
            my $cookie = first {$_->name eq 'Bugzilla_login'}
                                @{$cgi->{'Bugzilla_cookie_list'}};
            $user_id = $cookie->value if $cookie;
        }
    }

    # If no cookies were provided, we also look for a login token
    # passed in the parameters of a webservice
    my $token = $self->login_token;
    if ($token && (!$login_cookie || !$user_id)) {
        ($user_id, $login_cookie) = ($token->{'user_id'}, $token->{'login_token'});
    }

    my $ip_addr = remote_ip();

    if ($login_cookie && $user_id) {
        # Anything goes for these params - they're just strings which
        # we're going to verify against the db
        trick_taint($ip_addr);
        trick_taint($login_cookie);
        detaint_natural($user_id);

        my $is_valid =
          $dbh->selectrow_array('SELECT 1
                                   FROM logincookies
                                  WHERE cookie = ?
                                        AND userid = ?
                                        AND (ipaddr = ? OR ipaddr IS NULL)',
                                 undef, ($login_cookie, $user_id, $ip_addr));

        # If the cookie is valid, return a valid username.
        if ($is_valid) {
            # If we logged in successfully, then update the lastused 
            # time on the login cookie
            $dbh->do("UPDATE logincookies SET lastused = NOW() 
                       WHERE cookie = ?", undef, $login_cookie);
            return { user_id => $user_id };
        }
    }

    # Either the he cookie is invalid, or we got no cookie. We don't want 
    # to ever return AUTH_LOGINFAILED, because we don't want Bugzilla to 
    # actually throw an error when it gets a bad cookie. It should just 
    # look like there was no cookie to begin with.
    return { failure => AUTH_NODATA };
}

sub login_token {
    my ($self) = @_;
    my $input      = Bugzilla->input_params;
    my $usage_mode = Bugzilla->usage_mode;

    return $self->{'_login_token'} if exists $self->{'_login_token'};

    if ($usage_mode ne USAGE_MODE_XMLRPC
        && $usage_mode ne USAGE_MODE_JSON
        && $usage_mode ne USAGE_MODE_REST) {
        return $self->{'_login_token'} = undef;
    }

    # Check if a token was passed in via requests for WebServices
    my $token = trim(delete $input->{'Bugzilla_token'});
    return $self->{'_login_token'} = undef if !$token;

    my ($user_id, $login_token) = split('-', $token, 2);
    if (!detaint_natural($user_id) || !$login_token) {
        return $self->{'_login_token'} = undef;
    }

    return $self->{'_login_token'} = {
        user_id     => $user_id,
        login_token => $login_token
    };
}

1;
