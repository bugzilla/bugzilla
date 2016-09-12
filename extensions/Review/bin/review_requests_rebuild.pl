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
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::Extension::Review::Util;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

rebuild_review_counters(sub{
    my ($count, $total) = @_;
    indicate_progress({ current => $count, total => $total, every => 5 });
});
