# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Marc Schumann <wurblzap@gmail.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::WebService::Server;
use strict;
use Bugzilla::Util qw(ssl_require_redirect);
use Bugzilla::Error;

sub handle_login {
    my ($self, $class, $method, $full_method) = @_;
    eval "require $class";
    ThrowCodeError('unknown_method', {method => $full_method}) if $@;
    return if $class->login_exempt($method);
    Bugzilla->login();

    # Even though we check for the need to redirect in
    # Bugzilla->login() we check here again since Bugzilla->login()
    # does not know what the current XMLRPC method is. Therefore
    # ssl_require_redirect in Bugzilla->login() will have returned 
    # false if system was configured to redirect for authenticated 
    # sessions and the user was not yet logged in.
    # So here we pass in the method name to ssl_require_redirect so
    # it can then check for the extra case where the method equals
    # User.login, which we would then need to redirect if not
    # over a secure connection. 
    Bugzilla->cgi->require_https(Bugzilla->params->{'sslbase'})
        if ssl_require_redirect($full_method);
}

1;
