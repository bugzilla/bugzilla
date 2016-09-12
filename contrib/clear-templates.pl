#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Install::Filesystem qw(fix_dir_permissions);
use File::Path qw(mkpath rmtree);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
$| = 1;

# rename the current directory and create a new empty one
# the templates will lazy-compile on demand

my $path = bz_locations()->{'template_cache'};
my $delete_path = "$path.deleteme";

print "clearing $path\n";

rmtree("$delete_path") if -e "$delete_path";
rename($path, $delete_path)
    or die "renaming '$path' to '$delete_path' failed: $!\n";

mkpath($path)
    or die "creating '$path' failed: $!\n";
fix_dir_permissions($path);

# delete the temp directory (it's ok if this fails)

rmtree("$delete_path");
