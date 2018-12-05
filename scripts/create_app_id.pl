#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Usage: perl scripts/create_app_key.pl <callback_url> <description>

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;

use Digest::SHA qw(sha256_hex);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($callback, $description) = @ARGV;

if (!$callback || !$description) {
  die "Usage: scripts/create_app_key.pl <callback_url> <description>\n";
}

print sha256_hex($callback, $description);
