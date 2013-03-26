#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#
# report errors to arecibo
# expects a filename with a Data::Dumper serialised parameters
# called by Bugzilla::Arecibo
#

use strict;
use warnings;

use FindBin qw($Bin);
use lib $Bin;
use lib "$Bin/lib";

use Bugzilla;
use Bugzilla::Constants;
use File::Slurp;
use POSIX qw(setsid nice);
use Safe;
use Fcntl qw(:flock);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
nice(19);

# detach
open(STDIN, '</dev/null');
open(STDOUT, '>/dev/null');
open(STDERR, '>/dev/null');
setsid();

# grab arecibo server url
my $arecibo_server = Bugzilla->params->{arecibo_server} || '';
exit(1) unless $arecibo_server;

# read data dump
exit(1) unless my $filename = shift;
my $dump = read_file($filename);
unlink($filename);

# deserialise
my $cpt = new Safe;
$cpt->reval($dump) || exit(1);
my $data = ${$cpt->varglob('VAR1')};

# ensure we send warnings one at a time per webhead
flock(DATA, LOCK_EX);

# and post to arecibo
my $agent = LWP::UserAgent->new(
    agent   => 'bugzilla.mozilla.org',
    timeout => 10, # seconds
);
$agent->post($arecibo_server, $data);

__DATA__
this exists so the flock() code works.
do not remove this data section.
