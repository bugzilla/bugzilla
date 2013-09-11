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
use lib "$Bin/../../..";

use Bugzilla;
BEGIN { Bugzilla->extensions() }

use Bugzilla::Constants;
use Bugzilla::Extension::UserProfile::Util;
use Bugzilla::User;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
my $dbh = Bugzilla->dbh;
my $user_ids;
my $verbose = grep { $_ eq '-v' } @ARGV;

$user_ids = $dbh->selectcol_arrayref(
    "SELECT user_id
       FROM profiles_statistics_recalc
      ORDER BY user_id",
    { Slice => {} }
);

if (@$user_ids) {
    print "recalculating last_user_activity\n";
    my ($count, $total) = (0, scalar(@$user_ids));
    foreach my $user_id (@$user_ids) {
        if ($verbose) {
            $count++;
            my $login = user_id_to_login($user_id);
            print "$count/$total $login ($user_id)\n";
        }
        $dbh->do(
            "UPDATE profiles
                SET last_activity_ts = ?,
                    last_statistics_ts = NULL
            WHERE userid = ?",
            undef,
            last_user_activity($user_id),
            $user_id
        );
    }
    $dbh->do(
        "DELETE FROM profiles_statistics_recalc WHERE " . $dbh->sql_in('user_id', $user_ids)
    );
}

$user_ids = $dbh->selectcol_arrayref(
    "SELECT userid
       FROM profiles
      WHERE last_activity_ts IS NOT NULL
            AND (last_statistics_ts IS NULL
                 OR last_activity_ts > last_statistics_ts)
      ORDER BY userid",
    { Slice => {} }
);

if (@$user_ids) {
    $verbose && print "updating statistics\n";
    my ($count, $total) = (0, scalar(@$user_ids));
    foreach my $user_id (@$user_ids) {
        if ($verbose) {
            $count++;
            my $login = user_id_to_login($user_id);
            print "$count/$total $login ($user_id)\n";
        }
        update_statistics_by_user($user_id);
    }
}
