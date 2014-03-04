#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Status;
use Bugzilla::Util;

sub usage() {
  print <<USAGE;
Usage: fix_all_open_status_queries.pl <new_open_status>

E.g.: fix_all_open_status_queries.pl READY
This will add a new open state to user queries which currently look for
all open bugs by listing every open status in their query criteria.
For users who only look for bug_status=__open__, they will get the new
open status automatically.
USAGE
}

sub do_namedqueries {
    my ($new_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $replace_count = 0;

    my $query = $dbh->selectall_arrayref("SELECT id, query FROM namedqueries");

    if ($query) {
        $dbh->bz_start_transaction();

        my $sth = $dbh->prepare("UPDATE namedqueries SET query = ? WHERE id = ?");

        foreach my $row (@$query) {
            my ($id, $old_query) = @$row;
            my $new_query = all_open_states($new_status, $old_query);
            if ($new_query) {
                trick_taint($new_query);
                $sth->execute($new_query, $id);
                $replace_count++;
            }
        }

        $dbh->bz_commit_transaction();
    }

    print "namedqueries: $replace_count replacements made.\n";
}

# series
sub do_series {
    my ($new_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $replace_count = 0;

    my $query = $dbh->selectall_arrayref("SELECT series_id, query FROM series");

    if ($query) {
        $dbh->bz_start_transaction();

        my $sth = $dbh->prepare("UPDATE series SET query = ? WHERE series_id = ?");

        foreach my $row (@$query) {
            my ($series_id, $old_query) = @$row;
            my $new_query = all_open_states($new_status, $old_query);
            if ($new_query) {
                trick_taint($new_query);
                $sth->execute($new_query, $series_id);
                $replace_count++;
            }
        }

        $dbh->bz_commit_transaction();
    }

    print "series: $replace_count replacements made.\n";
}

sub all_open_states {
    my ($new_status, $query) = @_;

    my @open_states = Bugzilla::Status::BUG_STATE_OPEN();
    my $cgi = Bugzilla::CGI->new($query);
    my @query_states = $cgi->param('bug_status');

    my ($removed, $added) = diff_arrays(\@query_states, \@open_states);

    if (scalar @$added == 1 && $added->[0] eq $new_status) {
        push(@query_states, $new_status);
        $cgi->param('bug_status', @query_states);
        return $cgi->canonicalise_query();
    }

    return '';
}

sub validate_status {
    my ($status) = @_;
    my $dbh = Bugzilla->dbh;
    my $exists = $dbh->selectrow_array("SELECT 1 FROM bug_status 
                                        WHERE value = ?",
                                       undef, $status);
    return $exists ? 1 : 0;
}

#############################################################################
# MAIN CODE
#############################################################################
# This is a pure command line script.
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 1) {
    usage();
    exit(1);
}

my ($new_status) = @ARGV;

$new_status = uc($new_status);

if (!validate_status($new_status)) {
    print "Invalid status: $new_status\n\n";
    usage();
    exit(1);
}

print "Adding new status '$new_status'.\n\n";

do_namedqueries($new_status);
do_series($new_status);

# It's complex to determine which items now need to be flushed from memcached.
# As this is expected to be a rare event, we just flush the entire cache.
Bugzilla->memcached->clear_all();

exit(0);
