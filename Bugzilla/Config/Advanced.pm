# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::Advanced;

use 5.14.0;
use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 1700;

use constant get_param_list => (
  {
    name    => 'inbound_proxies',
    type    => 't',
    default => '',
    checker => \&check_inbound_proxies
  },

  {name => 'proxy_url', type => 't', default => ''},

  {
    name    => 'strict_transport_security',
    type    => 's',
    choices => ['off', 'this_domain_only', 'include_subdomains'],
    default => 'off',
    checker => \&check_multi
  },
);

sub check_inbound_proxies {
  my $inbound_proxies = shift;

  return "" if $inbound_proxies eq "*";
  my @proxies = split(/[\s,]+/, $inbound_proxies);
  foreach my $proxy (@proxies) {
    validate_ip($proxy) || return "$proxy is not a valid IPv4 or IPv6 address";
  }
  return "";
}

1;
