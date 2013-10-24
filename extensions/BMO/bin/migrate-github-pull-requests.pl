#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../../..";

use Bugzilla;
BEGIN { Bugzilla->extensions() }

use Bugzilla::Extension::BMO::Data;
use Bugzilla::Field;
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::User;
use Bugzilla::Util qw(trim);

my $dbh = Bugzilla->dbh;
my $nobody = Bugzilla::User->check({ name => 'nobody@mozilla.org' });
my $field = Bugzilla::Field->check({ name => 'attachments.mimetype' });

# grab list of suitable attachments

my $sql = <<EOF;
SELECT attachments.attach_id,
       attachments.bug_id,
       attachments.mimetype,
       attach_data.thedata
  FROM attachments
       INNER JOIN attach_data ON attach_data.id = attachments.attach_id
 WHERE ispatch = 0
       AND mimetype = 'text/plain'
       AND thedata IS NOT NULL
       AND LENGTH(thedata) > 0
       AND LENGTH(thedata) <= 256
EOF
print "Searching for suitable attachments..\n";
my $attachments = $dbh->selectall_arrayref($sql, { Slice => {} });
my ($current, $total, $updated) = (1, scalar(@$attachments), 0);

die "No suitable attachments found\n" unless $total;
print "About to check $total attachments for github pull requests, and\n";
print "update content-type if required.\n";
print "Press <enter> to start, or ^C to cancel...\n";
<>;

foreach my $attachment (@$attachments) {
    indicate_progress({ current => $current++, total => $total, every => 25 });

    # check payload
    my $url = trim($attachment->{thedata});
    next if $url =~ /\s/;
    next unless $url =~ m#^https://github\.com/[^/]+/[^/]+/pull/\d+\/?$#i;

    $dbh->bz_start_transaction;

    # set content-type
    $dbh->do(
        "UPDATE attachments SET mimetype = ? WHERE attach_id = ?",
        undef,
        GITHUB_PR_CONTENT_TYPE, $attachment->{attach_id}
    );

    # insert into bugs_activity
    my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    $dbh->do(
        "INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added)
                     VALUES (?, ?, ?, ?, ?, ?)",
        undef,
        $attachment->{bug_id}, $nobody->id, $timestamp, $field->id,
        $attachment->{mimetype}, GITHUB_PR_CONTENT_TYPE
    );
    $dbh->do(
        "UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
        undef,
        $timestamp, $timestamp, $attachment->{bug_id}
    );

    $dbh->bz_commit_transaction;
    $updated++;
}

print "Attachments updated: $updated\n";
