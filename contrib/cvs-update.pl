#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Keep a record of all cvs updates made from a given directory.
#
# Later, if changes need to be backed out, look at the log file
# and run the cvs command with the date that you want to back
# out to. (Probably the second to last entry).

# Because this script lives in contrib, you may want to
#   ln -s contrib/cvs-update.pl cvs-update.pl
# from your bugzilla install directory so you can run
# the script easily from there (./cvs-update.pl)

#DATE=`date +%e/%m/%Y\ %k:%M:%S\ %Z`

my ($second, $minute, $hour, $day, $month, $year) = gmtime;
my $date = sprintf("%04d-%02d-%02d %d:%02d:%02dZ",
                   $year+1900, $month+1, $day, $hour, $minute, $second);
my $cmd = "cvs -q update -dP";
open LOG, ">>cvs-update.log" or die("Couldn't open cvs update log!");
print LOG "$cmd -D \"$date\"\n";
close LOG;
system("$cmd -A");

# sample log file
#cvs update -P -D "11/04/2000 20:22:08 PDT"
#cvs update -P -D "11/05/2000 20:22:22 PDT"
#cvs update -P -D "11/07/2000 20:26:29 PDT"
#cvs update -P -D "11/08/2000 20:27:10 PDT"
