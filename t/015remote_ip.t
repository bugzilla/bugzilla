# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.14.0;
use strict;
use warnings;

use lib qw(. lib t local/lib/perl5);

use Test::More qw(no_plan);
use Bugzilla;
use Bugzilla::Util qw(remote_ip);

my $params = Bugzilla->params;

{
  local $params->{inbound_proxies} = '10.0.0.1,10.0.0.2';
  local $ENV{REMOTE_ADDR}          = '10.0.0.2';
  local $ENV{HTTP_X_FORWARDED_FOR} = '10.42.42.42';

  is(remote_ip(), '10.42.42.42', "from proxy 2");
}

{
  local $params->{inbound_proxies} = '10.0.0.1,10.0.0.2';
  local $ENV{REMOTE_ADDR}          = '10.0.0.1';
  local $ENV{HTTP_X_FORWARDED_FOR} = '10.42.42.42';

  is(remote_ip(), '10.42.42.42', "from proxy 1");
}

{
  local $params->{inbound_proxies} = '10.0.0.1,10.0.0.2';
  local $ENV{REMOTE_ADDR}          = '10.0.0.3';
  local $ENV{HTTP_X_FORWARDED_FOR} = '10.42.42.42';

  is(remote_ip(), '10.0.0.3', "not a proxy");
}

{
  local $params->{inbound_proxies} = '*';
  local $ENV{REMOTE_ADDR}          = '10.0.0.3';
  local $ENV{HTTP_X_FORWARDED_FOR} = '10.42.42.42,1.4.9.2';

  is(remote_ip(), '10.42.42.42', "always proxy");
}

{
  local $params->{inbound_proxies} = '';
  local $ENV{REMOTE_ADDR}          = '10.9.8.7';
  local $ENV{HTTP_X_FORWARDED_FOR} = '10.42.42.42,1.4.9.2';

  is(remote_ip(), '10.9.8.7', "never proxy");
}


{
  local $params->{inbound_proxies} = '10.0.0.1,2600:cafe::cafe:ffff:bf42:4998';
  local $ENV{REMOTE_ADDR}          = '2600:cafe::cafe:ffff:bf42:4998';
  local $ENV{HTTP_X_FORWARDED_FOR} = '2600:cafe::cafe:ffff:bf42:BEEF';

  is(remote_ip(), '2600:cafe::cafe:ffff:bf42:BEEF', "from proxy ipv6");
}

{
  local $params->{inbound_proxies} = '10.0.0.1,2600:cafe::cafe:ffff:bf42:4998';
  local $ENV{REMOTE_ADDR}          = '2600:cafe::cafe:ffff:bf42:DEAD';
  local $ENV{HTTP_X_FORWARDED_FOR} = '2600:cafe::cafe:ffff:bf42:BEEF';

  is(remote_ip(), '2600:cafe::cafe:ffff:bf42:DEAD', "invalid proxy ipv6");
}


{
  local $params->{inbound_proxies} = '*';
  local $ENV{REMOTE_ADDR}          = '2600:cafe::cafe:ffff:bf42:DEAD';
  local $ENV{HTTP_X_FORWARDED_FOR} = '';

  is(remote_ip(), '2600:cafe::cafe:ffff:bf42:DEAD', "always proxy ipv6");
}
