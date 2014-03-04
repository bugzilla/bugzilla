#!/usr/bin/perl -w
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Gervase Markham <gerv@gerv.net>

use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;

sub usage() {
  print <<USAGE;
Usage: fixqueries.pl <parameter> <oldvalue> <newvalue>

E.g.: fixqueries.pl product FoodReplicator SeaMonkey
will change all occurrences of "FoodReplicator" to "Seamonkey" in the 
appropriate places in the namedqueries, series and series_categories tables.
 
Note that all parameters are case-sensitive.
USAGE
}

sub do_namedqueries($$$) {
    my ($field, $old, $new) = @_;
    $old = url_quote($old);
    $new = url_quote($new);

    my $dbh = Bugzilla->dbh;
    #$dbh->bz_start_transaction();

    my $replace_count = 0;
    my $query = $dbh->selectall_arrayref("SELECT id, query FROM namedqueries");
    if ($query) {
        my $sth = $dbh->prepare("UPDATE namedqueries SET query = ? 
                                                     WHERE id = ?");
        
        foreach my $row (@$query) {
            my ($id, $query) = @$row;
            if ($query =~ /(?:^|&|;)$field=$old(?:&|$|;)/) {
                $query =~ s/((?:^|&|;)$field=)$old(;|&|$)/$1$new$2/;
                $sth->execute($query, $id);
                $replace_count++;
            }
        }
    }

    #$dbh->bz_commit_transaction();
    print "namedqueries: $replace_count replacements made.\n";
}
  
# series
sub do_series($$$) {
    my ($field, $old, $new) = @_;
    $old = url_quote($old);
    $new = url_quote($new);

    my $dbh = Bugzilla->dbh;
    #$dbh->bz_start_transaction();

    my $replace_count = 0;
    my $query = $dbh->selectall_arrayref("SELECT series_id, query 
                                          FROM series");
    if ($query) {
        my $sth = $dbh->prepare("UPDATE series SET query = ?
                                               WHERE series_id = ?");
        foreach my $row (@$query) {
            my ($series_id, $query) = @$row;
            
            if ($query =~ /(?:^|&|;)$field=$old(?:&|$|;)/) {
                $query =~ s/((?:^|&|;)$field=)$old(;|&|$)/$1$new$2/;
                $replace_count++;
            }
            
            $sth->execute($query, $series_id);
        }
    }

    #$dbh->bz_commit_transaction();
    print "series:      $replace_count replacements made.\n";
}
  
# series_categories
sub do_series_categories($$) {
    my ($old, $new) = @_;
    my $dbh = Bugzilla->dbh;

    $dbh->do("UPDATE series_categories SET name = ? WHERE name = ?", 
             undef, 
             ($new, $old));
}

#############################################################################
# MAIN CODE
#############################################################################
# This is a pure command line script.
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 3) {
    usage();
    exit();
}

my ($field, $old, $new) = @ARGV;

print "Changing all instances of '$old' to '$new'.\n\n";

do_namedqueries($field, $old, $new);
do_series($field, $old, $new);
do_series_categories($old, $new);

# It's complex to determine which items now need to be flushed from memcached.
# As this is expected to be a rare event, we just flush the entire cache.
Bugzilla->memcached->clear_all();

exit(0);

