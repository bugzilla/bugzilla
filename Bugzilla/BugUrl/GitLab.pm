# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::GitLab;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::BugUrl);

###############################
####        Methods        ####
###############################

sub should_handle {
  my ($class, $uri) = @_;

  # GitLab issue and merge request URLs can have the form:
  # https://gitlab.com/projectA/subprojectB/subprojectC/../(issues|merge_requests)/53
  return ($uri->path =~ m!^/.*/(issues|merge_requests)/\d+$!) ? 1 : 0;
}

sub _check_value {
  my ($class, $uri) = @_;

  $uri = $class->SUPER::_check_value($uri);

  # Require the HTTPS scheme.
  $uri->scheme('https');

  # Make sure there are no query parameters.
  $uri->query(undef);

  # And remove any # part if there is one.
  $uri->fragment(undef);

  return $uri;
}

1;
