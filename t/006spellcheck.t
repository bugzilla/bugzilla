# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.


#################
#Bugzilla Test 6#
####Spelling#####

use lib 't';
use Support::Files;

BEGIN { # yes the indenting is off, deal with it
#add the words to check here:
@evilwords = qw(
anyways
appearence
arbitary
cancelled
critera
databasa
dependan
existance
existant
paramater
refered
repsentation
suported
varsion
);

$testcount = scalar(@Support::Files::testitems);
}

use Test::More tests => $testcount;

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

# at last, here we actually run the test...
my $evilwordsregexp = join('|', @evilwords);

foreach my $file (@testitems) {
    $file =~ s/\s.*$//; # nuke everything after the first space (#comment)
    next if (!$file); # skip null entries

    if (open (FILE, $file)) { # open the file for reading

        my $found_word = '';

        while (my $file_line = <FILE>) { # and go through the file line by line
            if ($file_line =~ /($evilwordsregexp)/i) { # found an evil word
                $found_word = $1;
                last;
            }
        }
            
        close (FILE);
            
        if ($found_word) {
            ok(0,"$file: found SPELLING ERROR $found_word --WARNING");
        } else {
            ok(1,"$file does not contain registered spelling errors");
        }
    } else {
        ok(0,"could not open $file for spellcheck --WARNING");
    }
} 

exit 0;
