#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;

use Cwd 'abs_path';
use File::Basename;
use FindBin;
use lib "$FindBin::Bin/../..";
use lib "$FindBin::Bin/../../lib";

use Bugzilla;
use Bugzilla::Constants;

sub usage() {
  print <<USAGE;
Usage: convert_date_time_date.pl <column>

E.g.: convert_date_time_date.pl cf_due_date
Converts a datetime field (FIELD_TYPE_DATETIME) to a date field type
(FIELD_TYPE_DATE).

Note: Any time portion will be lost but the date portion will be preserved.
USAGE
}

#############################################################################
# MAIN CODE
#############################################################################

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 1) {
    usage();
    exit();
}

my $column = shift;

print <<EOF;
Converting bugs.${column} from FIELD_TYPE_DATETIME to FIELD_TYPE_DATE.

Note: Any time portion will be lost but the date portion will be preserved.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

Bugzilla->dbh->bz_alter_column('bugs', $column, { TYPE => 'DATE' });
Bugzilla->dbh->do("UPDATE fielddefs SET type = ? WHERE name = ?",
                  undef, FIELD_TYPE_DATE, $column);

# It's complex to determine which items now need to be flushed from memcached.
# As this is expected to be a rare event, we just flush the entire cache.
Bugzilla->memcached->clear_all();

print "\ndone.\n";
