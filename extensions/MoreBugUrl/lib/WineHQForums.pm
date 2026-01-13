# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MoreBugUrl::WineHQForums;

use 5.14.0;
use strict;
use warnings;

use base qw(Bugzilla::BugUrl);

###############################
####        Methods        ####
###############################

sub should_handle {
  my ($class, $uri) = @_;

  # WineHQ Forums URLs only have one form:
  #   http(s)://forum.winehq.org/viewtopic.php?f=1234&t=1234
  return (lc($uri->authority) eq 'forum.winehq.org'
    and $uri->path =~ m|^/viewtopic\.php$|
    and $uri->query_param('f') =~ /^\d+$/
    and $uri->query_param('t') =~ /^\d+$/) ? 1 : 0;
}

sub _check_value {
  my $class = shift;

  my $uri = $class->SUPER::_check_value(@_);

  # WineHQ Forums HTTP URLs redirect to HTTPS, so just use the HTTPS
  # scheme.
  $uri->scheme('https');

  # Remove any # part if there is one.
  $uri->fragment(undef);

  return $uri;
}

1;