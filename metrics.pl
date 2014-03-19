#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

BEGIN {
    delete $ENV{SERVER_SOFTWARE};
}

use FindBin qw($Bin);
use lib $Bin;
use lib "$Bin/lib";

use Bugzilla;
use Bugzilla::Constants;
use POSIX qw(setsid nice);

Bugzilla->metrics_enabled(0);
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
nice(19);

# grab reporter class and filename
exit(1) unless my $reporter_class = shift;
exit(1) unless my $filename = shift;

# create reporter object and report
eval "use $reporter_class";

# detach
if ($reporter_class->DETACH) {
    open(STDIN, '</dev/null');
    open(STDOUT, '>/dev/null');
    open(STDERR, '>/dev/null');
    setsid();
}

# report
exit(1) unless my $reporter = $reporter_class->new({ json_filename => $filename });
$reporter->report();
