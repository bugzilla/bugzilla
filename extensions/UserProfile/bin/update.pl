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

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $user_ids = Bugzilla->dbh->selectcol_arrayref(
    "SELECT userid
       FROM profiles
      WHERE last_activity_ts IS NOT NULL
            AND (last_statistics_ts IS NULL
                 OR last_activity_ts > last_statistics_ts)
      ORDER BY userid",
    { Slice => {} }
);

foreach my $user_id (@$user_ids) {
    update_statistics_by_user($user_id);
}
