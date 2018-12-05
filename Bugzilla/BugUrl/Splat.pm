# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::Splat;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::BugUrl);

sub should_handle {
  my ($class, $uri) = @_;
  return $uri =~ m#^https?://hellosplat\.com/s/beanbag/tickets/\d+#;
}

sub _check_value {
  my ($class, $uri) = @_;
  $uri = $class->SUPER::_check_value($uri);
  $uri->scheme('https');    # force https
  return $uri;
}

1;
