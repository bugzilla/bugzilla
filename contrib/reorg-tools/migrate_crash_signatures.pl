#!/usr/bin/perl 
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis,  WITHOUT WARRANTY OF ANY KIND,  either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Initial Developer of the Original Code is Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
#===============================================================================
#
#         FILE:  migrate_crash_signatures.pl
#
#        USAGE:  ./migrate_crash_signatures.pl  
#
#  DESCRIPTION:  Migrate current summary data on matched bugs to the
#                new cf_crash_signature custom fields.
#
#      OPTIONS:  No params, then performs dry-run without updating the database.
#                If a true value is passed as single argument, then the database
#                is updated.
# REQUIREMENTS:  None
#         BUGS:  577724
#        NOTES:  None
#       AUTHOR:  David Lawrence (dkl@mozilla.com), 
#      COMPANY:  Mozilla Corproation
#      VERSION:  1.0
#      CREATED:  05/31/2011 03:57:52 PM
#     REVISION:  1
#===============================================================================

use strict;
use warnings;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;

use Data::Dumper;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $UPDATE_DB = shift; # Pass true value as single argument to perform database update

my $dbh = Bugzilla->dbh;

# User to make changes as
my $user_id = $dbh->selectrow_array(
    "SELECT userid FROM profiles WHERE login_name='nobody\@mozilla.org'");
$user_id or die "Can't find user ID for 'nobody\@mozilla.org'\n";

my $field_id = $dbh->selectrow_array(
    "SELECT id FROM fielddefs WHERE name = 'cf_crash_signature'");
$field_id or die "Can't find field ID for 'cf_crash_signature' field\n";

# Search criteria
# a) crash or topcrash keyword,  
# b) not have [notacrash] in whiteboard,  
# c) have a properly formulated [@ ...]

# crash and topcrash keyword ids
my $crash_keyword_id = $dbh->selectrow_array(
    "SELECT id FROM keyworddefs WHERE name = 'crash'");
$crash_keyword_id or die "Can't find keyword id for 'crash'\n";

my $topcrash_keyword_id = $dbh->selectrow_array(
    "SELECT id FROM keyworddefs WHERE name = 'topcrash'");
$topcrash_keyword_id or die "Can't find keyword id for 'topcrash'\n";

# main search query
my $bugs = $dbh->selectall_arrayref("
    SELECT bugs.bug_id, bugs.short_desc
      FROM bugs LEFT JOIN keywords ON bugs.bug_id = keywords.bug_id
     WHERE (keywords.keywordid = ? OR keywords.keywordid = ?)
           AND bugs.status_whiteboard NOT REGEXP '\\\\[notacrash\\\\]'
           AND bugs.short_desc REGEXP '\\\\[@.+\\\\]'
           AND (bugs.cf_crash_signature IS NULL OR bugs.cf_crash_signature = '')
  ORDER BY bugs.bug_id",
    {'Slice' => {}}, $crash_keyword_id, $topcrash_keyword_id);

my $bug_count = scalar @$bugs;
$bug_count or die "No bugs were found in matching search criteria.\n";

print "Migrating $bug_count bugs to new crash signature field\n";

$dbh->bz_start_transaction() if $UPDATE_DB;

foreach my $bug (@$bugs) {
    my $bug_id  = $bug->{'bug_id'};
    my $summary = $bug->{'short_desc'};

    print "Updating bug $bug_id ...";
   
    my @signatures;
    while ($summary =~ /(\[\@(?:\[.*\]|[^\[])*\])/g) {
        push(@signatures, $1);
    }
 
    if (@signatures && $UPDATE_DB) {
        my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
	    $dbh->do("UPDATE bugs SET cf_crash_signature = ? WHERE bug_id = ?",
		         undef, join("\n", @signatures), $bug_id);
    	$dbh->do("INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) " .
       	         "VALUES (?, ?, ?, ?, '', ?)",
                 undef, $bug_id, $user_id, $timestamp, $field_id, join("\n", @signatures));
        $dbh->do("UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?", 
                 undef, $timestamp, $timestamp, $bug_id);
    }
    elsif (@signatures) {
	    print Dumper(\@signatures);
    }

    print "done.\n";
}

$dbh->bz_commit_transaction() if $UPDATE_DB;
