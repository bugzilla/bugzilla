#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);




use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Product;
use Bugzilla::User;
use Getopt::Long;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $config = {
    connector => '',
    warn      => 5,
    alarm     => 10,
};

my $usage = <<EOF;
DESCRIPTION

  this script is called by nagios to warn/alarm when a push connector is
  backlogged.

SYNTAX

  --connector  (required) connector's name (eg. ReviewBoard)
  --warn       (optional) number of messages that trigger a warning (def: 5)
  --alarm      (optional) number of messages that trigger an alarm (def: 10)

EXAMPLES

  nagios_push_checker.pl --connector ReviewBoard
  nagios_push_checker.pl --connector TCL --warn 25 --alarm 50
EOF

die($usage) unless GetOptions(
    'connector=s' => \$config->{connector},
    'warn=i'      => \$config->{warn},
    'alarm=i'     => \$config->{alarm},
    'help|?'      => \$config->{help},
);
die $usage if $config->{help} || !$config->{connector};

#

use constant NAGIOS_OK          => 0;
use constant NAGIOS_WARNING     => 1;
use constant NAGIOS_CRITICAL    => 2;
use constant NAGIOS_NAMES       => [qw( OK WARNING CRITICAL )];

my $dbh = Bugzilla->switch_to_shadow_db;

my ($count) = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM push_backlog WHERE connector=?",
    undef,
    $config->{connector},
);

my $state;
if ($count >= $config->{alarm}) {
    $state = NAGIOS_CRITICAL;
} elsif ($count >= $config->{warn}) {
    $state = NAGIOS_WARNING;
} else {
    $state = NAGIOS_OK;
}

print "push ", NAGIOS_NAMES->[$state], ": ", $count, " ",
      "push.", $config->{connector}, " message",
      ($count == 1 ? '' : 's'), " in backlog\n";
exit $state;
