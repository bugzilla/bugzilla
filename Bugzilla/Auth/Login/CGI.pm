# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Auth::Login::CGI;

use 5.10.1;
use strict;

use parent qw(Bugzilla::Auth::Login);
use constant user_can_create_account => 1;

use Bugzilla::Constants;
use Bugzilla::WebService::Constants;
use Bugzilla::Util;
use Bugzilla::Error;

sub get_login_info {
    my ($self) = @_;
    my $params = Bugzilla->input_params;

    my $username = trim(delete $params->{"Bugzilla_login"});
    my $password = delete $params->{"Bugzilla_password"};

    if (!defined $username || !defined $password) {
        return { failure => AUTH_NODATA };
    }

    return { username => $username, password => $password };
}

sub fail_nodata {
    my ($self) = @_;
    my $cgi = Bugzilla->cgi;
    my $template = Bugzilla->template;

    if (Bugzilla->usage_mode != USAGE_MODE_BROWSER) {
        ThrowUserError('login_required');
    }

    print $cgi->header();
    $template->process("account/auth/login.html.tmpl",
                       { 'target' => $cgi->url(-relative=>1) }) 
        || ThrowTemplateError($template->error());
    exit;
}

1;
