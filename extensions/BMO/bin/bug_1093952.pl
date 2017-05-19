#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use 5.10.1;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Component;
use Bugzilla::Constants qw( USAGE_MODE_CMDLINE );
use Bugzilla::Field;
use Bugzilla::Product;
use Bugzilla::User;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

my $infra     = Bugzilla::Product->check({ name => 'Infrastructure & Operations' });
my $relops_id = Bugzilla::Component->check({ product => $infra, name => 'RelOps' })->id;
my $puppet_id = Bugzilla::Component->check({ product => $infra, name => 'RelOps: Puppet' })->id;
my $infra_id  = $infra->id;
my $components = $dbh->sql_in('component_id', [ $relops_id, $puppet_id ]);

print "Searching for bugs..\n";
my $bugs = $dbh->selectall_arrayref(<<EOF, { Slice => {} });
    SELECT
        bug_id,
        product_id,
        component_id,
        status_whiteboard
    FROM
        bugs
    WHERE
    (
        (product_id = $infra_id)
        AND NOT ($components)
        AND (status_whiteboard LIKE '%[kanban:engops:https://mozilla.kanbanize.com/ctrl_board/6/%')
    ) OR (
        status_whiteboard LIKE '%[kanban:engops:https://kanbanize.com/ctrl_board/6/%'
    )
EOF
die "No suitable bugs found\n" unless @$bugs;
printf "About to fix %s bugs\n", scalar(@$bugs);
print "Press <Ctrl-C> to stop or <Enter> to continue...\n";
getc();

my $nobody = Bugzilla::User->check({ name => 'nobody@mozilla.org' });
my $field  = Bugzilla::Field->check({ name => 'status_whiteboard' });
my $when   = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

my $sth_bugs = $dbh->prepare("
    UPDATE bugs
       SET status_whiteboard = ?,
           delta_ts = ?,
           lastdiffed = ?
     WHERE bug_id = ?
");
my $sth_activity = $dbh->prepare("
    INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added)
    VALUES (?, ?, ?, ?, ?, ?)
");

$dbh->bz_start_transaction();
foreach my $bug (@$bugs) {
    my $bug_id = $bug->{bug_id};
    my $whiteboard = $bug->{status_whiteboard};
    print "bug $bug_id\n  $whiteboard\n";

    my $updated = $whiteboard;
    $updated =~ s#\[kanban:engops:https://kanbanize\.com/ctrl_board/6/[^\]]*\]\s*##g;
    if ($bug->{product_id} == $infra->id
        && $bug->{component_id} != $relops_id
        && $bug->{component_id} != $puppet_id
    ) {
        $updated =~ s#\[kanban:engops:https://mozilla\.kanbanize\.com/ctrl_board/6/[^\]]*\]\s*##g;
    }
    print "  $updated\n";

    $sth_bugs->execute($updated, $when, $when, $bug_id);
    $sth_activity->execute($bug_id, $nobody->id, $when, $field->id, $whiteboard, $updated);
}
$dbh->bz_commit_transaction();

print "Done.\n";
