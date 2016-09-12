#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use FindBin '$RealBin';
use lib "$RealBin/../../..";
use lib "$RealBin/../../../lib";
use lib "$RealBin/../lib";

use Bugzilla;
use Bugzilla::Constants;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

# Number of jobs required in the queue before we alert

use constant WARN_COUNT         => 500;
use constant ALARM_COUNT        => 750;

use constant NAGIOS_OK          => 0;
use constant NAGIOS_WARNING     => 1;
use constant NAGIOS_CRITICAL    => 2;

my $connector = shift
    || die "Syntax: $0 connector\neg. $0 TCL\n";
$connector = uc($connector);

my $sql = <<EOF;
    SELECT COUNT(*)
      FROM push_backlog
     WHERE connector = ?
EOF

my $dbh = Bugzilla->switch_to_shadow_db;
my ($count) = @{ $dbh->selectcol_arrayref($sql, undef, $connector) };

if ($count < WARN_COUNT) {
    print "push $connector OK: $count messages found.\n";
    exit NAGIOS_OK;
} elsif ($count < ALARM_COUNT) {
    print "push $connector WARNING: $count messages found.\n";
    exit NAGIOS_WARNING;
} else {
    print "push $connector CRITICAL: $count messages found.\n";
    exit NAGIOS_CRITICAL;
}
