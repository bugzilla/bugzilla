#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);




use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::DB;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $bugs_dbh    = Bugzilla->dbh;
my $localconfig = Bugzilla->localconfig;

my $root_mysql_pw = shift;
defined $root_mysql_pw || die "MySQL root password required.\n";

my $mysql_dbh = Bugzilla::DB::_connect({
    db_driver => $localconfig->{db_driver},
    db_host   => $localconfig->{db_host},
    db_name   => 'mysql',
    db_user   => 'root',
    db_pass   => $root_mysql_pw
});

# Check that the mysql timezones are populated and up to date
my $mysql_tz_install
  = "Please populate using instuctions at http://dev.mysql.com/doc/refman/5.6/en/time-zone-support.html#time-zone-installation and re-run this script.";
my $mysql_tz_count = $mysql_dbh->selectrow_array("SELECT COUNT(*) FROM mysql.time_zone_name");
$mysql_tz_count
  || die "The timezone table mysql.time_zone_name has not been populated.\n$mysql_tz_install\n";
my $mysql_tz_date1 = $mysql_dbh->selectrow_array("SELECT CONVERT_TZ('2007-03-11 2:00:00','US/Eastern','US/Central')");
my $mysql_tz_date2 = $mysql_dbh->selectrow_array("SELECT CONVERT_TZ('2007-03-11 3:00:00','US/Eastern','US/Central')");
($mysql_tz_date1 eq $mysql_tz_date2)
  || die "The timezone table mysql.time_zone_name needs to be updated.\n$mysql_tz_install\n";

my $rows = $mysql_dbh->selectall_arrayref(
    "SELECT TABLE_NAME, COLUMN_NAME
       FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = ?
            AND DATA_TYPE='datetime'",
    undef, Bugzilla->localconfig->{db_name});
my $total = scalar @$rows;

if (!$total) {
    print "No DATETIME columns found.\n";
    exit;
}

print STDERR <<EOF;
About to convert $total DATETIME columns to TIMESTAMP columns and migrate their values from PST to UTC.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

# Store any indexes we may need to drop/add later
my %indexes;
foreach my $row (@$rows) {
    my ($table, $column) = @$row;
    next if exists $indexes{$table} && exists $indexes{$table}{$column};
    my $table_info = $bugs_dbh->bz_table_info($table);
    next if !exists $table_info->{INDEXES};
    my $table_indexes = $table_info->{INDEXES};
    for (my $i = 0; $i < @$table_indexes; $i++) {
        my $name       = $table_indexes->[$i];
        my $definition = $table_indexes->[$i+1];
        if ((ref $definition eq 'HASH' && grep($column eq $_, @{ $definition->{FIELDS} }))
                || (ref $definition eq 'ARRAY' && grep($column eq $_, @$definition)))
        {
            $indexes{$table} ||= {};
            $indexes{$table}->{$column} = { name => $name, definition => $definition };
            last;
        }
    }
}

my @errors;
foreach my $row (@$rows) {
    my ($table, $column) = @$row;

    if (my $column_info = $bugs_dbh->bz_column_info($table, $column)) {
        say "Converting $table.$column to TIMESTAMP...";

        # Drop any indexes first
        if (exists $indexes{$table} && exists $indexes{$table}->{$column}) {
            my $index_name = $indexes{$table}->{$column}->{name};
            $bugs_dbh->bz_drop_index($table, $index_name);
        }

        # Rename current column to PST
        $bugs_dbh->bz_rename_column($table, $column, $column . "_pst");

        # Create the new UTC column
        $column_info->{TYPE} = 'TIMESTAMP';
        $column_info->{DEFAULT} = 'CURRENT_TIMESTAMP' if $column_info->{NOTNULL} && !$column_info->{DEFAULT};
        $bugs_dbh->bz_add_column($table, $column, $column_info);

        # Migrate the PST value to UTC
        $bugs_dbh->do("UPDATE $table SET $column = CONVERT_TZ(" . $column . '_pst' . ", 'America/Los_Angeles', 'UTC')");

        # Drop the old PST column
        $bugs_dbh->bz_drop_column($table, $column . '_pst');

        # And finally recreate the index if one existed for this column
        if (exists $indexes{$table} && exists $indexes{$table}->{$column}) {
            my $index_info = $indexes{$table}->{$column};
            $bugs_dbh->bz_add_index($table, $index_info->{name}, $index_info->{definition});
        }
    }
    else {
        push(@errors, "$table.$column does not exist in bz_schema and will need to fixed manually.");
    }
}

if (@errors) {
    print "Errors:\n" . join("\n", @errors) . "\n";
}
