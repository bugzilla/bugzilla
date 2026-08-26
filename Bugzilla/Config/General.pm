# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::General;

use 5.14.0;
use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 150;

use constant get_param_list => (
  {
    name     => 'maintainer',
    type     => 't',
    no_reset => '1',
    default  => '',
    checker  => \&check_email
  },

  {
    name    => 'utf8',
    type    => 's',
    choices => ['1', 'utf8', 'utf8mb3', 'utf8mb4'],
    default => 'utf8mb4',
    checker => \&check_utf8
  },

  {
    name     => 'utf8_collate',
    type     => 'r',
    no_reset => '1',
    default  => 'utf8mb4_unicode_520_ci',
  },


  {name => 'shutdownhtml', type => 'l', default => ''},

  {name => 'announcehtml', type => 'l', default => ''},

  {
    name    => 'upgrade_notification',
    type    => 's',
    choices => [
      'development_snapshot',  'latest_stable_release',
      'stable_branch_release', 'disabled'
    ],
    default => 'latest_stable_release',
    checker => \&check_notification
  },
);

1;
