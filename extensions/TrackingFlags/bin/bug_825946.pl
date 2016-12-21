#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

BEGIN {
    use Bugzilla;
    Bugzilla->extensions;
}

use Bugzilla::Constants qw( USAGE_MODE_CMDLINE );
use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::User;
use Bugzilla::Bug qw(LogActivityEntry);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
my $dbh = Bugzilla->dbh;
my $user = Bugzilla::User->check({name => 'nobody@mozilla.org'});

my $tf_vis = $dbh->selectall_arrayref(<<SQL);
    SELECT
        tracking_flag_id,
        product_id,
        component_id
    FROM
        tracking_flags_visibility
SQL

my $tf_bugs = $dbh->selectall_arrayref(<<SQL);
    SELECT
        tf.name,
        tf_bugs.value,
        bugs.bug_id,
        tf_bugs.tracking_flag_id,
        bugs.product_id,
        bugs.component_id
    FROM
        tracking_flags_bugs AS tf_bugs
    JOIN bugs USING (bug_id)
    JOIN tracking_flags AS tf ON tf.id = tf_bugs.tracking_flag_id
SQL

my %visible;
foreach my $row (@$tf_vis) {
    my ($tracking_flag_id, $product_id, $component_id) = @$row;
    $visible{$tracking_flag_id}{$product_id}{$component_id // 'ALL'} = 1;
}

my %bugs = map { $_->[0] => 1 } @$tf_bugs;
my $bugs = keys %bugs;

printf "About to check %d tracking flags on %d bugs\n", @$tf_bugs + 0, $bugs;
print "Press <Ctrl-C> to stop or <Enter> to continue...\n";
getc();

my $removed = 0;
$dbh->bz_start_transaction();
my ($timestamp) = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
foreach my $tf_bug (@$tf_bugs) {
    my ($flag_name, $value, $bug_id, $tf_id, $product_id, $component_id) = @$tf_bug;
    unless ($visible{$tf_id}{$product_id}{$component_id} || $visible{$tf_id}{$product_id}{ALL}) {
        $dbh->do("DELETE FROM tracking_flags_bugs WHERE tracking_flag_id = ? AND bug_id = ?",
                 undef, $tf_id, $bug_id);
        LogActivityEntry($bug_id, $flag_name, $value, '---', $user->id, $timestamp);
        $removed++;
    }
}
$dbh->bz_commit_transaction();

print "Removed $removed tracking flags\n";
print "Done.\n";
