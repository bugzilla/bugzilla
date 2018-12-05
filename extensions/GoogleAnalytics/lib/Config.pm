# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GoogleAnalytics::Config;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;

sub get_param_list {
  my ($class) = @_;

  my @params = (
    {
      name    => 'google_analytics_tracking_id',
      type    => 't',
      default => '',
      checker => sub {
        my ($tracking_id) = (@_);

        return 'must be like UA-XXXXXX-X'
          unless $tracking_id =~ m{^(UA-[[:xdigit:]]+-[[:xdigit:]]+)?$};
        return '';
      }
    },
    {name => 'google_analytics_debug', type => 'b', default => 0},
  );

  return @params;
}

1;
