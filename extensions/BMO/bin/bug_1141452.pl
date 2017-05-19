#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use 5.10.1;

use lib qw(. lib local/lib/perl5);

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
my $flags = $dbh->selectall_arrayref(<<EOF, { Slice => {} }, $blocking_b2g->flag_id, $tracking_b2g->flag_id);
    SELECT
        bugs.bug_id,
        blocking_b2g.id id,
        tracking_b2g.value value
    FROM
        bugs
        INNER JOIN tracking_flags_bugs blocking_b2g
            ON blocking_b2g.bug_id = bugs.bug_id AND blocking_b2g.tracking_flag_id = ?
        LEFT JOIN tracking_flags_bugs tracking_b2g
            ON tracking_b2g.bug_id = bugs.bug_id AND tracking_b2g.tracking_flag_id = ?
    WHERE
        blocking_b2g.value = 'backlog'
EOF
die "No suitable bugs found\n" unless @$flags;
printf "About to fix %s bugs\n", scalar(@$flags);
print "Press <Ctrl-C> to stop or <Enter> to continue...\n";
getc();

my $nobody = Bugzilla::User->check({ name => 'nobody@mozilla.org' });
my $when   = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

$dbh->bz_start_transaction();
foreach my $flag (@$flags) {
    if (!$flag->{value}) {
        print $flag->{bug_id}, ": changing blocking_b2g:backlog -> tracking_b2g:backlog\n";
        # no tracking_b2g value, change blocking_b2g:backlog -> tracking_b2g:backlog
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
    elsif ($flag->{value}) {
        print $flag->{bug_id}, ": deleting blocking_b2g:backlog\n";
        # tracking_b2g already has a value, just delete blocking_b2g:backlog
        $dbh->do(
            "DELETE FROM tracking_flags_bugs WHERE id = ?",
            undef,
            $flag->{id},
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
    }
}
$dbh->bz_commit_transaction();

print "Done.\n";
