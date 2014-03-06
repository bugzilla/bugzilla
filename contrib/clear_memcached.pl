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
use lib "$Bin/..";
use lib "$Bin/../lib";

use Bugzilla;
use Bugzilla::Constants;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (Bugzilla->memcached->{memcached}) {
    Bugzilla->memcached->clear_all();
    print "memcached cleared\n";
} else {
    print "memcached is not enabled\n";
}
