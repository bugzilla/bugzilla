#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
$| = 1;

use FindBin qw($Bin);
use lib "$Bin/../../..";

use Bugzilla;
BEGIN { Bugzilla->extensions() }

use Bugzilla::Constants;
use Bugzilla::Extension::UserProfile::Util;
use Bugzilla::Install::Util qw(indicate_progress);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
my $dbh = Bugzilla->dbh;

my $user_ids = $dbh->selectcol_arrayref(
    "SELECT userid
       FROM profiles
      WHERE last_activity_ts IS NULL
      ORDER BY userid"
);

my ($current, $total) = (1, scalar(@$user_ids));
foreach my $user_id (@$user_ids) {
    indicate_progress({ current => $current++, total => $total, every => 25 });
    my $ts = last_user_activity($user_id);
    next unless $ts;
    $dbh->do(
        "UPDATE profiles SET last_activity_ts = ? WHERE userid = ?",
        undef,
        $ts, $user_id);
}
