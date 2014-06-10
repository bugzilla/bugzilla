#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;

use FindBin '$RealBin';
use lib "$RealBin/../..", "$RealBin/../../lib";

use Bugzilla;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Hook;
use Bugzilla::Product;
use Bugzilla::Util;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 3) {
    die <<USAGE;
Usage: movecomponent.pl <oldproduct> <newproduct> <component>

E.g.: movecomponent.pl ReplicationEngine FoodReplicator SeaMonkey
will move the component "SeaMonkey" from the product "ReplicationEngine"
to the product "FoodReplicator".

Important: You must make sure the milestones and versions of the bugs in the
component are available in the new product. See syncmsandversions.pl.

USAGE
}

my ($old_product_name, $new_product_name, $component_name) = @ARGV;
my $old_product = Bugzilla::Product->check({ name => $old_product_name });
my $new_product = Bugzilla::Product->check({ name => $new_product_name });
my $component   = Bugzilla::Component->check({ product => $old_product, name => $component_name });
my $field_id    = get_field_id('product');

my $dbh = Bugzilla->dbh;

# check versions
my @missing_versions;
my $ra_versions = $dbh->selectcol_arrayref(
    "SELECT DISTINCT version FROM bugs WHERE component_id = ?",
    undef, $component->id);
foreach my $version (@$ra_versions) {
    my $has_version = $dbh->selectrow_array(
        "SELECT 1 FROM versions WHERE product_id = ? AND value = ?",
        undef, $new_product->id, $version);
    push @missing_versions, $version unless $has_version;
}

# check milestones
my @missing_milestones;
my $ra_milestones = $dbh->selectcol_arrayref(
    "SELECT DISTINCT target_milestone FROM bugs WHERE component_id = ?",
    undef, $component->id);
foreach my $milestone (@$ra_milestones) {
    my $has_milestone = $dbh->selectrow_array(
        "SELECT 1 FROM milestones WHERE product_id=? AND value=?",
        undef, $new_product->id, $milestone);
    push @missing_milestones, $milestone unless $has_milestone;
}

my $missing_error = '';
if (@missing_versions) {
    $missing_error .= "'$new_product_name' is missing the following version(s):\n  " .
        join("\n  ", @missing_versions) . "\n";
}
if (@missing_milestones) {
    $missing_error .= "'$new_product_name' is missing the following milestone(s):\n  " .
        join("\n  ", @missing_milestones) . "\n";
}
die $missing_error if $missing_error;

# confirmation
print <<EOF;
About to move the component '$component_name'
From '$old_product_name'
To '$new_product_name'

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

print "Moving '$component_name' from '$old_product_name' to '$new_product_name'...\n\n";
$dbh->bz_start_transaction();

my $ra_ids = $dbh->selectcol_arrayref(
    "SELECT bug_id FROM bugs WHERE product_id=? AND component_id=?",
    undef, $old_product->id, $component->id);

# Bugs table
$dbh->do("UPDATE bugs SET product_id = ? WHERE component_id = ?",
         undef,
         ($new_product->id, $component->id));

# Flags tables
$dbh->do("UPDATE flaginclusions SET product_id = ? WHERE component_id = ?",
         undef,
         ($new_product->id, $component->id));

$dbh->do("UPDATE flagexclusions SET product_id = ? WHERE component_id = ?",
         undef,
         ($new_product->id, $component->id));

# Components
$dbh->do("UPDATE components SET product_id = ? WHERE id = ?",
         undef,
         ($new_product->id, $component->id));

Bugzilla::Hook::process('reorg_move_component', {
    old_product => $old_product,
    new_product => $new_product,
    component   => $component,
} );

# Mark bugs as touched
$dbh->do("UPDATE bugs SET delta_ts = NOW()
          WHERE component_id = ?", undef, $component->id);
$dbh->do("UPDATE bugs SET lastdiffed = NOW()
          WHERE component_id = ?", undef, $component->id);

# Update bugs_activity
my $userid = 1; # nobody@mozilla.org

$dbh->do("INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed,
                                    added)
             SELECT bug_id, ?, delta_ts, ?, ?, ?
             FROM bugs WHERE component_id = ?",
         undef,
         ($userid, $field_id, $old_product_name, $new_product_name, $component->id));

Bugzilla::Hook::process('reorg_move_bugs', { bug_ids => $ra_ids } );

$dbh->bz_commit_transaction();

# It's complex to determine which items now need to be flushed from memcached.
# As this is expected to be a rare event, we just flush the entire cache.
Bugzilla->memcached->clear_all();
