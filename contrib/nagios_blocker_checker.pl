#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/..";
use lib "$Bin/../lib";

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::User qw(login_to_id);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

# Time in hours to wait before paging/warning

use constant ALERT_TIMES => {
    'major.alarm'       => 24,
    'major.warn'        => 20,
    'critical.alarm'    => 8,
    'critical.warn'     => 5,
    'blocker.alarm'     => 0,
    'blocker.warn'      => 0,
};

use constant NAGIOS_OK          => 0;
use constant NAGIOS_WARNING     => 1;
use constant NAGIOS_CRITICAL    => 2;
use constant NAGIOS_NAMES       => [qw( OK WARNING CRITICAL )];

my $assignee = shift
    || die "Syntax: $0 assignee\neg.  $0 server-ops\@mozilla-org.bugs\n";
login_to_id($assignee, 1);

my $sql = <<EOF;
    SELECT bug_id, bug_severity, UNIX_TIMESTAMP(bugs.creation_ts) AS ts
      FROM bugs
           INNER JOIN profiles map_assigned_to ON bugs.assigned_to = map_assigned_to.userid
     WHERE map_assigned_to.login_name = ?
           AND COALESCE(resolution, '') = ''
           AND bug_severity IN ('blocker', 'critical', 'major')
EOF

my $bugs = {
    'major'     => [],
    'critical'  => [],
    'blocker'   => [],
};
my $current_state = NAGIOS_OK;
my $current_time = time;

my $dbh = Bugzilla->switch_to_shadow_db;
foreach my $bug (@{ $dbh->selectall_arrayref($sql, { Slice => {} }, $assignee) }) {
    my $severity = $bug->{bug_severity};
    my $age = ($current_time - $bug->{ts}) / 3600;

    if ($age > ALERT_TIMES->{"$severity.alarm"}) {
        $current_state = NAGIOS_CRITICAL;
        push @{$bugs->{$severity}}, "https://bugzil.la/" . $bug->{bug_id};

    } elsif ($age > ALERT_TIMES->{"$severity.warn"}) {
        if ($current_state < NAGIOS_WARNING) {
            $current_state = NAGIOS_WARNING;
        }
        push @{$bugs->{$severity}}, "https://bugzil.la/" . $bug->{bug_id};

    }
}

print "bugs " . NAGIOS_NAMES->[$current_state] . ": ";
if ($current_state == NAGIOS_OK) {
    print "No blocker, critical, or major bugs found."
}
foreach my $severity (qw( blocker critical major )) {
    my $list = $bugs->{$severity};
    if (@$list) {
        printf "%s %s bug(s) found " . join(' , ', @$list) . " ", scalar(@$list), $severity;
    }
}
print "\n";

exit $current_state;
