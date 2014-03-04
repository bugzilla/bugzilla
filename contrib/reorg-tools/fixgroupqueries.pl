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
Usage: fixgroupqueries.pl <oldvalue> <newvalue>

E.g.: fixgroupqueries.pl w-security webtools-security
will change all occurrences of "w-security" to "webtools-security" in the 
appropriate places in the namedqueries.
 
Note that all parameters are case-sensitive.
USAGE
}

sub do_namedqueries($$) {
    my ($old, $new) = @_;
    $old = url_quote($old);
    $new = url_quote($new);

    my $dbh = Bugzilla->dbh;

    my $replace_count = 0;
    my $query = $dbh->selectall_arrayref("SELECT id, query FROM namedqueries");
    if ($query) {
        my $sth = $dbh->prepare("UPDATE namedqueries SET query = ? 
                                                     WHERE id = ?");
        
        foreach my $row (@$query) {
            my ($id, $query) = @$row;
            if (($query =~ /field\d+-\d+-\d+=bug_group/) &&
                ($query =~ /(?:^|&|;)value\d+-\d+-\d+=$old(?:;|&|$)/)) {
                $query =~ s/((?:^|&|;)value\d+-\d+-\d+=)$old(;|&|$)/$1$new$2/;
                $sth->execute($query, $id);
                $replace_count++;
            }
        }
    }

    print "namedqueries: $replace_count replacements made.\n";
}

# series
sub do_series($$) {
    my ($old, $new) = @_;
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

            if (($query =~ /field\d+-\d+-\d+=bug_group/) &&
                ($query =~ /(?:^|&|;)value\d+-\d+-\d+=$old(?:;|&|$)/)) {
                $query =~ s/((?:^|&|;)value\d+-\d+-\d+=)$old(;|&|$)/$1$new$2/;
                $sth->execute($query, $series_id);
                $replace_count++;
            }
        }
    }

    #$dbh->bz_commit_transaction();
    print "series:      $replace_count replacements made.\n";
}

#############################################################################
# MAIN CODE
#############################################################################
# This is a pure command line script.
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 2) {
    usage();
    exit();
}

my ($old, $new) = @ARGV;

print "Changing all instances of '$old' to '$new'.\n\n";

#do_namedqueries($old, $new);
do_series($old, $new);

# It's complex to determine which items now need to be flushed from memcached.
# As this is expected to be a rare event, we just flush the entire cache.
Bugzilla->memcached->clear_all();

exit(0);
