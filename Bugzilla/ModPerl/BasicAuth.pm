# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::ModPerl::BasicAuth;
use 5.10.1;
use strict;
use warnings;

# Protects a mod_perl <Location> with Basic HTTP authentication.
#
# Example use:
#
# <Location "/ses">
#   PerlAuthenHandler Bugzilla::ModPerl::BasicAuth
#   PerlSetEnv AUTH_VAR_NAME ses_username
#   PerlSetEnv AUTH_VAR_PASS ses_password
#   AuthName SES
#   AuthType Basic
#   require valid-user
# </Location>
#
# AUTH_VAR_NAME and AUTH_VAR_PASS are the names of variables defined in
# `localconfig` which hold the authentication credentials.

use Apache2::Const -compile => qw(OK HTTP_UNAUTHORIZED);
use Bugzilla ();

sub handler {
    my $r = shift;
    my ($status, $password) = $r->get_basic_auth_pw;
    return $status if $status != Apache2::Const::OK;

    my $auth_var_name = $ENV{AUTH_VAR_NAME};
    my $auth_var_pass = $ENV{AUTH_VAR_PASS};
    unless ($auth_var_name && $auth_var_pass) {
        warn "AUTH_VAR_NAME and AUTH_VAR_PASS environmental vars not set\n";
        $r->note_basic_auth_failure;
        return Apache2::Const::HTTP_UNAUTHORIZED;
    }

    my $auth_user = Bugzilla->localconfig->{$auth_var_name};
    my $auth_pass = Bugzilla->localconfig->{$auth_var_pass};
    unless ($auth_user && $auth_pass) {
        warn "$auth_var_name and $auth_var_pass not configured\n";
        $r->note_basic_auth_failure;
        return Apache2::Const::HTTP_UNAUTHORIZED;
    }

    unless ($r->user eq $auth_user && $password eq $auth_pass) {
        $r->note_basic_auth_failure;
        return Apache2::Const::HTTP_UNAUTHORIZED;
    }

    return Apache2::Const::OK;
}

1;
