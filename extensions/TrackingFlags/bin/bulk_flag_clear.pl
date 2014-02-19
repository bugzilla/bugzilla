#!/usr/bin/perl -w
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

BEGIN {
    use Bugzilla;
    Bugzilla->extensions;
}

use Bugzilla::Constants;
use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::Extension::TrackingFlags::Flag::Bug;
use Bugzilla::User;

use Getopt::Long;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $config = {};
GetOptions(
    $config,
    "trace=i",
    "update_db",
    "flag=s",
    "modified_before=s",
    "modified_after=s",
    "value=s"
) or exit;
unless ($config->{flag}
        && ($config->{modified_before}
            || $config->{modified_after}
            || $config->{value}))
{
    die <<EOF;
$0
  clears tracking flags matching the specified criteria.
  the last-modified will be updated, however bugmail will not be generated.

SYNTAX
  $0 --flag <flag> (conditions) [--update_db]

CONDITIONS
  --modified_before <datetime>      bug last-modified before <datetime>
  --modified_after <datetime>       bug last-modified after <datetime>
  --value <flag value>              flag = <flag value>

OPTIONS
  --update_db : by default only the impacted bugs will be listed.  pass this
                switch to update the database.
EOF
}

# build sql

my (@where, @values);

my $flag = Bugzilla::Extension::TrackingFlags::Flag->check({ name => $config->{flag} });
push @where, 'tracking_flags_bugs.tracking_flag_id = ?';
push @values, $flag->flag_id;

if ($config->{modified_before}) {
    push @where, 'bugs.delta_ts < ?';
    push @values, $config->{modified_before};
}

if ($config->{modified_after}) {
    push @where, 'bugs.delta_ts > ?';
    push @values, $config->{modified_after};
}

if ($config->{value}) {
    push @where, 'tracking_flags_bugs.value = ?';
    push @values, $config->{value};
}

my $sql = "
    SELECT tracking_flags_bugs.bug_id
      FROM tracking_flags_bugs
           INNER JOIN bugs ON bugs.bug_id = tracking_flags_bugs.bug_id
     WHERE (" . join(") AND (", @where) . ")
     ORDER BY tracking_flags_bugs.bug_id
";

# execute query

my $dbh = Bugzilla->dbh;
$dbh->{TraceLevel} = $config->{trace} if $config->{trace};

my $bug_ids = $dbh->selectcol_arrayref($sql, undef, @values);

if (!@$bug_ids) {
    die "no matching bugs found\n";
}

if (!$config->{update_db}) {
    print "bugs found: ", scalar(@$bug_ids), "\n\n", join(',', @$bug_ids), "\n\n";
    print "--update_db not provided, no changes made to the database\n";
    exit;
}

# update bugs

my $nobody = Bugzilla::User->check({ name => 'nobody@mozilla.org' });
# put our nobody user into all groups to avoid permissions issues
$nobody->{groups} = [Bugzilla::Group->get_all];
Bugzilla->set_user($nobody);

foreach my $bug_id (@$bug_ids) {
    print "updating bug $bug_id\n";
    $dbh->bz_start_transaction;

    # update the bug
    # this will deal with history for us but not send bugmail
    my $bug = Bugzilla::Bug->check({ id => $bug_id });
    $bug->set_all({ $flag->name => '---' });
    $bug->update;

    # update lastdiffed to skip bugmail for this change
    $dbh->do(
        "UPDATE bugs SET lastdiffed = delta_ts WHERE bug_id = ?",
        undef,
        $bug->id
    );
    $dbh->bz_commit_transaction;
}
