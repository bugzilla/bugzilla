#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License,  v. 2.0. If a copy of the MPL was not distributed with this
# file,  You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses",  as
# defined by the Mozilla Public License,  v. 2.0.
#===============================================================================
#
#         FILE:  migrate_whiteboard_keyword.pl
#
#        USAGE:  ./migrate_whiteboard_keyword.pl [--remove]
#
#  DESCRIPTION:  Add keyword to bugs with specified string stored in
#                whiteboard field. If --remove, then also remove the string
#                value from whiteboard.
#
#      OPTIONS:  Without --doit, does a dry-run without updating the database.
#                If --doit is passed, then the database is updated.
#                --remove will remove string from the whiteboard.
# REQUIREMENTS:  None
#         BUGS:  1279368
#        NOTES:  None
#       AUTHOR:  David Lawrence (dkl@mozilla.com),
#      COMPANY:  Mozilla Corproation
#      VERSION:  1.0
#      CREATED:  10/31/2012
#     REVISION:  1
#===============================================================================

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);


use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Keyword;
use Bugzilla::User;
use Bugzilla::Util qw(trick_taint trim);

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
Usage: migrate_whiteboard_keyword.pl [--remove|-r] [--help|-h] [--doit]

E.g.: migrate_whiteboard_keyword.pl --remove --doit "good first bug" "good-first-bug"
This script will add the specified keyword to any bugs that
contain a string in the status whiteboard. If the --remove option is
given, then string will be removed from the whiteboard as well.

Pass --doit to make the database changes permanent.
USAGE
    exit(1);
}

# exit if help was requested
usage() if $help;

# grab whiteboard and keyword
my $whiteboard = shift;
my $keyword = shift;
($whiteboard && $keyword) || usage("Whiteboard or keyword strings were not provided\n");
trick_taint($whiteboard);
trick_taint($keyword);

# User to make changes as automation@bmo.tld
my $auto_user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
$auto_user || usage("Can't find user 'automation\@bmo.tld'\n");

# field ids for logging activity
my $keyword_field = Bugzilla::Field->new({ name => 'keywords'});
$keyword_field || usage("Can't find field 'keywords'\n");
my $whiteboard_field = Bugzilla::Field->new({ name => 'status_whiteboard' });
$whiteboard_field || usage("Can't find field 'status_whiteboard'\n");

# keyword object (assumes already created)
my $keyword_obj = Bugzilla::Keyword->new({ name => $keyword });
$keyword_obj || usage("Can't find keyword '$keyword'\n");

my $dbh = Bugzilla->dbh;

my $bugs = $dbh->selectall_arrayref("SELECT DISTINCT bugs.bug_id, bugs.status_whiteboard
                                     FROM bugs WHERE bugs.status_whiteboard LIKE ?",
                                    { Slice => {} }, '%' . $whiteboard . '%');

my $bug_count = scalar @$bugs;
$bug_count || usage("No bugs were found in matching search criteria.\n");

print colored(['green'], "Processing $bug_count bug(s)\n");

$dbh->bz_start_transaction() if $doit;

foreach my $bug (@$bugs) {
    my $bug_id = $bug->{'bug_id'};
    my $status_whiteboard = $bug->{'status_whiteboard'};

    print "working on bug $bug_id\n";

    my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

    my $keyword_present = $dbh->selectrow_array("
        SELECT bug_id FROM keywords WHERE bug_id = ? AND keywordid = ?",
        undef, $bug_id, $keyword_obj->id);

    if (!$keyword_present) {
        print "  adding keyword\n";
        if ($doit) {
            $dbh->do("INSERT INTO keywords (bug_id, keywordid) VALUES (?, ?)",
                     undef, $bug_id, $keyword_obj->id);
            $dbh->do("INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) " .
                     "VALUES (?, ?, ?, ?, '', ?)",
                     undef, $bug_id, $auto_user->id, $timestamp, $keyword_field->id, $keyword);
            $dbh->do("UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
                     undef, $timestamp, $timestamp, $bug_id);
        }
    }

    if ($remove_whiteboard) {
        print "  removing whiteboard\n";
        if ($doit) {
            my $old_whiteboard = $status_whiteboard;
            $status_whiteboard =~ s/\Q$whiteboard\E//ig;
            $status_whiteboard = trim($status_whiteboard);

            $dbh->do("UPDATE bugs SET status_whiteboard = ? WHERE bug_id = ?",
                     undef, $status_whiteboard, $bug_id);
            $dbh->do("INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) " .
                     "VALUES (?, ?, ?, ?, ?, ?)",
                     undef, $bug_id, $auto_user->id, $timestamp, $whiteboard_field->id, $old_whiteboard, $status_whiteboard);
            $dbh->do("UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
                     undef, $timestamp, $timestamp, $bug_id);
        }
    }
}

$dbh->bz_commit_transaction() if $doit;

if ($doit) {
    # It's complex to determine which items now need to be flushed from memcached.
    # As this is expected to be a rare event, we just flush the entire cache.
    Bugzilla->memcached->clear_all();

    print colored(['green'], "DATABASE WAS UPDATED\n");
}
else {
    print colored(['red'], "DATABASE WAS NOT UPDATED\n");
}

exit(0);
