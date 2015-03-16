#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../../..";

BEGIN {
    use Bugzilla;
    Bugzilla->extensions;
}

use Bugzilla::Constants qw( USAGE_MODE_CMDLINE );
use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::User;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
my $dbh = Bugzilla->dbh;

my $blocking_b2g = Bugzilla::Extension::TrackingFlags::Flag->check({ name => 'cf_blocking_b2g' });
my $tracking_b2g = Bugzilla::Extension::TrackingFlags::Flag->check({ name => 'cf_tracking_b2g' });

die "tracking-b2g does not have a 'backlog' value\n"
    unless grep { $_->value eq 'backlog' } @{ $tracking_b2g->values };

print "Searching for bugs..\n";
my $flags = $dbh->selectall_arrayref(<<EOF, { Slice => {} }, $blocking_b2g->flag_id);
    SELECT
        id,
        bug_id
    FROM
        tracking_flags_bugs
    WHERE
        tracking_flag_id = ?
        AND value = 'backlog'
EOF
die "No suitable bugs found\n" unless @$flags;
printf "About to fix %s bugs\n", scalar(@$flags);
print "Press <Ctrl-C> to stop or <Enter> to continue...\n";
getc();

my $nobody = Bugzilla::User->check({ name => 'nobody@mozilla.org' });
my $when   = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

$dbh->bz_start_transaction();
foreach my $flag (@$flags) {
    $dbh->do(
        "UPDATE tracking_flags_bugs SET tracking_flag_id = ? WHERE id = ?",
        undef,
        $tracking_b2g->flag_id, $flag->{id},
    );
    $dbh->do(
        "UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
        undef,
        $when, $when, $flag->{bug_id},
    );
    $dbh->do(
        "INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) VALUES (?, ?, ?, ?, ?, ?)",
        undef,
        $flag->{bug_id}, $nobody->id, $when, $blocking_b2g->id, 'backlog', '---',
    );
    $dbh->do(
        "INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) VALUES (?, ?, ?, ?, ?, ?)",
        undef,
        $flag->{bug_id}, $nobody->id, $when, $tracking_b2g->id, '---', 'backlog',
    );
}
$dbh->bz_commit_transaction();

print "Done.\n";
