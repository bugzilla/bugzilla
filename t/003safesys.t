# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.


#################
#Bugzilla Test 3#
###Safesystem####

use strict;

use lib 't';

use Support::Files;

use Test::More tests => scalar(@Support::Files::testitems);

# Capture the TESTOUT from Test::More or Test::Builder for printing errors.
# This will handle verbosity for us automatically.
my $fh;
{
    local $^W = 0;  # Don't complain about non-existent filehandles
    if (-e \*Test::More::TESTOUT) {
        $fh = \*Test::More::TESTOUT;
    } elsif (-e \*Test::Builder::TESTOUT) {
        $fh = \*Test::Builder::TESTOUT;
    } else {
        $fh = \*STDOUT;
    }
}

my @testitems = @Support::Files::testitems; 
my $perlapp = "\"$^X\"";

foreach my $file (@testitems) {
    $file =~ s/\s.*$//; # nuke everything after the first space (#comment)
    next if (!$file); # skip null entries
    my $command = "$perlapp -c -It -MSupport::Systemexec $file 2>&1";
    my $loginfo=`$command`;
    if ($loginfo =~ /arguments for Support::Systemexec::(system|exec)/im) {
        ok(0,"$file DOES NOT use proper system or exec calls");
        print $fh $loginfo;
    } else {
        ok(1,"$file uses proper system and exec calls");
    }
}

exit 0;
