# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::WebCompat;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::BugUrl);

###############################
####        Methods        ####
###############################

sub should_handle {
  my ($class, $uri) = @_;

  # https://webcompat.com/issues/1111
  my $host = lc($uri->authority);
  return ($host eq 'webcompat.com' || $host eq 'www.webcompat.com')
    && $uri->path =~ m#^/issues/\d+$#;
}

sub _check_value {
  my ($class, $uri) = @_;
  $uri = $class->SUPER::_check_value($uri);

  # force https and drop www from host
  $uri->scheme('https');
  $uri->authority('webcompat.com');
  return $uri;
}

1;
