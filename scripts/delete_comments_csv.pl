#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Comment;
use Bugzilla::Constants;

use Text::CSV_XS;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $auto_user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
Bugzilla->set_user($auto_user);

my $dbh = Bugzilla->dbh;

my $filename = shift;
$filename || die "No CSV file provided.\n";

open(CSV, $filename) || die "Could not open CSV file: $!\n";

$dbh->bz_start_transaction;

my $csv = Text::CSV_XS->new();
while (my $line = <CSV>) {
    $csv->parse($line);
    my @values = $csv->fields();
    next if !@values;
    my ($bug_id, $comment_id) = @values;
    next if $bug_id !~ /^\d+$/;
    print "Deleting comment '$comment_id' from bug '$bug_id' ";
    my $bug = Bugzilla::Bug->check({ id => $bug_id });
    my $comment = Bugzilla::Comment->new($comment_id);
    if (!$comment || $comment->bug_id ne $bug_id) {
        print "... commment '$comment_id' does not exist ... skipping.\n";
        next;
    }
    $comment->remove_from_db();
    $bug->_sync_fulltext( update_comments => 1 );
    print "... done.\n";
}

$dbh->bz_commit_transaction;

close(CSV) || die "Could not close CSV file: $!\n";
