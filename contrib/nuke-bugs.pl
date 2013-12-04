#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;

use lib qw(.);

use Bugzilla;
use Bugzilla::Constants;

use Getopt::Long;

# This SQL is designed to delete the bugs and other activity in a Bugzilla database
# so that one can use for development purposes or to start using it as a fresh installation.
# Other data will be retained such as products, versions, flags, profiles, etc.

$| = 1;
my $trace = 0;

GetOptions("trace" => \$trace) || exit;

my $dbh = Bugzilla->dbh;

$dbh->{TraceLevel} = 1 if $trace;

print <<EOF;
WARNING - This will delete all bugs, hit <enter> to continue or <ctrl-c> to cancel - WARNING
EOF
getc();

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

$dbh->bz_start_transaction();

print "Deleting all bug data...\n";

delete_from_table('bug_group_map');
delete_from_table('bugs_activity');
delete_from_table('cc');
delete_from_table('dependencies');
delete_from_table('duplicates');
delete_from_table('flags');
delete_from_table('keywords');
delete_from_table('attach_data');
delete_from_table('attachments');
delete_from_table('bug_group_map');
delete_from_table('bugs');
delete_from_table('longdescs');

$dbh->do("ALTER TABLE bugs AUTO_INCREMENT = 1"); # MySQL specific

$dbh->bz_commit_transaction();

# This has to happen outside of the transaction
$dbh->do("DELETE FROM bugs_fulltext");

print "All done!\n";

sub delete_from_table {
    my $table = shift;
    print "Deleting from $table...";
    $dbh->do("DELETE FROM $table");
    print "done.\n";
}
