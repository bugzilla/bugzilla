#!/usr/bin/perl -w
#
# Updates the version of YUI3 used by Bugzilla. Just pass the path to
# an unzipped yui release directory, like:
#
#  contrib/new-yui3.pl /path/to/yui3/
#

use strict;

use File::Copy::Recursive qw(dircopy);
use File::Find;
use File::Basename;

my $SOURCE_PATH = shift;
my $DEST_PATH = shift;


dircopy("$SOURCE_PATH/build", $DEST_PATH) || die $!;

find(
    sub {
        my $delete = 0;
        my $filename = basename $File::Find::name;
        if ($filename =~ /-debug\.js$/
            || $filename =~ /-coverage\.js$/
            || $filename =~ /-skin\.css$/)

        {
            $delete = 1;
        }
        elsif ($filename =~ /-min\.js/) {
            $filename =~ s/-min//;
            $delete = 1;
        }
        return if !$delete;
        print "deleting $filename\n";
        unlink($filename) || die $!;
    },
    $DEST_PATH
);
