# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Webhooks::Config;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;

sub get_param_list {
  my ($class) = @_;

  my @param_list = (
    {name => 'webhooks_enabled', type => 'b', default => '0',},

    {
      name    => 'webhooks_group',
      type    => 's',
      choices => \&get_all_group_names,
      default => 'admin',
      checker => \&check_group
    },
  );
  return @param_list;
}

1;
