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

use Bugzilla;
use Bugzilla::Constants qw( USAGE_MODE_CMDLINE );
BEGIN { Bugzilla->extensions() }

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

my $sql = q{
    SELECT flags.id FROM flags
    INNER  JOIN bugs ON bugs.bug_id = flags.bug_id
    WHERE type_id = 748
      AND bugs.product_id != 21
};

print "Searching for suitable flags..\n";
my $flag_ids = $dbh->selectcol_arrayref($sql);
my $total    = @$flag_ids;

die "No suitable flags found\n" unless $total;
print "About to fix $total flags\n";
print "Press <enter> to start, or ^C to cancel...\n";
readline;

my $update_fsa_sql= "UPDATE flag_state_activity SET type_id = 4 WHERE " . $dbh->sql_in('flag_id', $flag_ids);
my $update_flags_sql = "UPDATE flags SET type_id = 4 WHERE " . $dbh->sql_in('id', $flag_ids);

$dbh->bz_start_transaction();
$dbh->do($update_fsa_sql);
$dbh->do($update_flags_sql);
$dbh->bz_commit_transaction();

Bugzilla->memcached->clear_all();

print "Done.\n";
