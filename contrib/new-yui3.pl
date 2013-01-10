#!/usr/bin/perl -w
#
# Updates the version of YUI3 used by Bugzilla. Just pass the path to
# an unzipped yui release directory, like:
#
#  contrib/new-yui3.pl /path/to/yui3/
#

use strict;

use FindBin;
use File::Find;
use File::Basename;

use constant EXCLUDES => qw(
    gallery-*
);

sub usage {
    my $error = shift;
    print "$error\n";
    print <<USAGE;
Usage: contrib/new-yui3.pl /path/to/yui3/files

Eg. contrib/new-yui3.pl /home/dkl/downloads/yui3
The yui3 directory should contain the 'build' directory
from the downloaded YUI3 tarball containing the module
related files.
USAGE
    exit(1);
}

#############
# Main Code #
#############

my $SOURCE_PATH = shift;
my $DEST_PATH   = "$FindBin::Bin/../js/yui3";

if (!$SOURCE_PATH || !-d "$SOURCE_PATH/build") {
    usage("Source path not found!");
}

mkdir($DEST_PATH) unless -d $DEST_PATH;

my $exclude_string = join(" ", map { "--exclude $_" } EXCLUDES);
my $command = "rsync -av --delete $exclude_string " .
              "$SOURCE_PATH/build/ $DEST_PATH/";
system($command) == 0 or usage("system '$command' failed: $?");

find(
    sub {
        my $delete = 0;
        my $filename = basename $File::Find::name;
        if ($filename =~ /-debug\.js$/
            || $filename =~ /-coverage\.js$/)
        {
            $delete = 1;
        }
        elsif ($filename =~ /-skin\.css$/) {
            my $temp_filename = $filename;
            $temp_filename =~ s/-skin//;
            if (-e $temp_filename) {
                $delete = 1;
            }
        }
        elsif ($filename =~ /-min\.js/) {
            $filename =~ s/-min//;
            if (-e $filename) {
                $delete = 1;
            }
        }
        return if !$delete;
        print "deleting $filename\n";
        unlink($filename) || usage($!);
    },
    $DEST_PATH
);

exit(0);
