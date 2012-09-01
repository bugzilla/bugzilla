# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::PatchViewer;

use 5.10.1;
use strict;

use Bugzilla::Config::Common;

our $sortkey = 1300;

sub get_param_list {
  my $class = shift;
  my @param_list = (
  {
   name    => 'cvsroot',
   type    => 't',
   default => '',
  },

  {
   name    => 'cvsroot_get',
   type    => 't',
   default => '',
  },

  {
   name    => 'bonsai_url',
   type    => 't',
   default => ''
  },

  {
   name    => 'lxr_url',
   type    => 't',
   default => ''
  },

  {
   name    => 'lxr_root',
   type    => 't',
   default => '',
  } );
  return @param_list;
}

1;
