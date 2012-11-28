#!/usr/bin/perl -wT
# This Source Code Form is subject to the terms of the Mozilla Public
# License,  v. 2.0. If a copy of the MPL was not distributed with this
# file,  You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses",  as
# defined by the Mozilla Public License,  v. 2.0.
#===============================================================================
#
#         FILE:  migrate_orange_bugs.pl
#
#        USAGE:  ./migrate_orange_bugs.pl [--remove]
#
#  DESCRIPTION:  Add intermittent-keyword to bugs with [orange] stored in
#                whiteboard field. If --remove, then also remove the [orange]
#                value from whiteboard.
#
#      OPTIONS:  Without --doit, does a dry-run without updating the database.
#                If --doit is passed, then the database is updated.
#                --remove will remove [orange] from the whiteboard.
# REQUIREMENTS:  None
#         BUGS:  791758
#        NOTES:  None
#       AUTHOR:  David Lawrence (dkl@mozilla.com),
#      COMPANY:  Mozilla Corproation
#      VERSION:  1.0
#      CREATED:  10/31/2012
#     REVISION:  1
#===============================================================================

use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::User;
use Bugzilla::Keyword;

use Getopt::Long;
use Term::ANSIColor qw(colored);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($remove_whiteboard, $help, $doit);
GetOptions("r|remove" => \$remove_whiteboard,
           "h|help" => \$help, 'doit' => \$doit);

sub usage {
    my $error = shift || "";
    print colored(['red'], $error) if $error;
    print <<USAGE;
Usage: migrate_orange_bugs.pl [--remove|-r] [--help|-h] [--doit]

E.g.: migrate_orange_bugs.pl --remove --doit
This script will add the intermittent-failure keyword to any bugs that
contant [orange] in the status whiteboard. If the --remove option is
given, then [orange] will be removed from the whiteboard as well.

Pass --doit to make the database changes permanent.
USAGE
    exit(1);
}

# Exit if help was requested
usage() if $help;

# User to make changes as
my $user_id = login_to_id('nobody@mozilla.org');
$user_id or usage("Can't find user ID for 'nobody\@mozilla.org'\n");

my $keywords_field_id = get_field_id('keywords');
$keywords_field_id or usage("Can't find field ID for 'keywords' field\n");

my $whiteboard_field_id = get_field_id('status_whiteboard');
$whiteboard_field_id or usage("Can't find field ID for 'whiteboard' field\n");

# intermittent-keyword id (assumes already created)
my $keyword_obj = Bugzilla::Keyword->new({ name => 'intermittent-failure' });
$keyword_obj or usage("Can't find keyword id for 'intermittent-failure'\n");
my $keyword_id = $keyword_obj->id;

my $dbh = Bugzilla->dbh;

my $bugs = $dbh->selectall_arrayref("
    SELECT DISTINCT bugs.bug_id, bugs.status_whiteboard
    FROM bugs WHERE bugs.status_whiteboard LIKE '%[orange]%'
    OR bugs.status_whiteboard LIKE '%[tb-orange]%'",
    {'Slice' => {}});

my $bug_count = scalar @$bugs;
$bug_count or usage("No bugs were found in matching search criteria.\n");

print colored(['green'], "Processing $bug_count [orange] bugs\n");

$dbh->bz_start_transaction() if $doit;

foreach my $bug (@$bugs) {
    my $bug_id     = $bug->{'bug_id'};
    my $whiteboard = $bug->{'status_whiteboard'};

    print "Checking bug $bug_id ... ";

    my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

    my $keyword_present = $dbh->selectrow_array("
        SELECT bug_id FROM keywords WHERE bug_id = ? AND keywordid = ?",
        undef, $bug_id, $keyword_id);

    if (!$keyword_present) {
        print "adding keyword ... ";

        if ($doit) {
            $dbh->do("INSERT INTO keywords (bug_id, keywordid) VALUES (?, ?)",
                     undef, $bug_id, $keyword_id);
            $dbh->do("INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) " .
       	             "VALUES (?, ?, ?, ?, '', 'intermittent-failure')",
                     undef, $bug_id, $user_id, $timestamp, $keywords_field_id);
            $dbh->do("UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
                     undef, $timestamp, $timestamp, $bug_id);
        }
    }

    if ($remove_whiteboard) {
        print "removing whiteboard ... ";

        if ($doit) {
            my $old_whiteboard = $whiteboard;
            $whiteboard =~ s/\[(tb-)?orange\]//ig;

            $dbh->do("UPDATE bugs SET status_whiteboard = ? WHERE bug_id = ?",
                     undef, $whiteboard, $bug_id);
            $dbh->do("INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) " .
       	             "VALUES (?, ?, ?, ?, ?, ?)",
                     undef, $bug_id, $user_id, $timestamp, $whiteboard_field_id, $old_whiteboard, $whiteboard);
            $dbh->do("UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
                     undef, $timestamp, $timestamp, $bug_id);
        }
    }

    print "done.\n";
}

$dbh->bz_commit_transaction() if $doit;

if ($doit) {
    print colored(['green'], "DATABASE WAS UPDATED\n");
}
else {
    print colored(['red'], "DATABASE WAS NOT UPDATED\n");
}

exit(0);
