# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::Edge;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::BugUrl);

use Bugzilla::Error;
use Bugzilla::Util;
use List::MoreUtils qw( any );

###############################
####        Methods        ####
###############################

# Example: https://developer.microsoft.com/en-us/microsoft-edge/platform/issues/9713176/
# Example 2: https://wpdev.uservoice.com/forums/257854/
#            https://wpdev.uservoice.com/forums/257854/suggestions/17420707
#            https://wpdev.uservoice.com/forums/257854-microsoft-edge-developer/suggestions/17420707-implement-css-display-flow-root-modern-clearfi
sub should_handle {
    my ($class, $uri) = @_;
    return any { lc($uri->authority) eq $_ } qw( developer.microsoft.com wpdev.uservoice.com );
}

sub _check_value {
    my ($class, $uri) = @_;

    $uri = $class->SUPER::_check_value($uri);

    return $uri if  $uri->path =~ m{^/en-us/microsoft-edge/platform/issues/\d+/$};
    return $uri if $uri->path =~ m{^/forums/\d+(?:-[^/]+)?/suggestions/\d+(?:-[^/]+)?};

    ThrowUserError('bug_url_invalid', { url => "$uri" });
}

1;
