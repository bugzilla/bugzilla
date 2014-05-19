# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::MozSupport;
use strict;
use base qw(Bugzilla::BugUrl);

###############################
####        Methods        ####
###############################

sub should_handle {
    my ($class, $uri) = @_;

    # Mozilla support questions normally have the form:
    # https://support.mozilla.org/<language>/questions/<id>
    return ($uri->authority =~ /^support.mozilla.org$/i
            and $uri->path =~ m|^(/[^/]+)?/questions/\d+$|) ? 1 : 0;
}

sub _check_value {
    my ($class, $uri) = @_;

    $uri = $class->SUPER::_check_value($uri);

    # Support.mozilla.org redirects to https automatically
    $uri->scheme('https');

    return $uri;
}

1;
