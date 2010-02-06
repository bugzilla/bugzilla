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

use Bugzilla::Error;

sub handle_login {
    my ($self, $class, $method, $full_method) = @_;
    eval "require $class";
    ThrowCodeError('unknown_method', {method => $full_method}) if $@;
    return if ($class->login_exempt($method) 
               and !defined Bugzilla->input_params->{Bugzilla_login});
    Bugzilla->login();
}

1;
