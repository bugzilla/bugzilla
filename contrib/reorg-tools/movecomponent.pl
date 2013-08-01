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

# See also https://bugzilla.mozilla.org/show_bug.cgi?id=119569
#

use strict;

use Cwd 'abs_path';
use File::Basename;
BEGIN {
    my $root = abs_path(dirname(__FILE__) . '/../..');
    chdir($root);
}
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Hook;
use Bugzilla::Util;

sub usage() {
    print <<USAGE;
Usage: movecomponent.pl <oldproduct> <newproduct> <component> <doit>

E.g.: movecomponent.pl ReplicationEngine FoodReplicator SeaMonkey
will move the component "SeaMonkey" from the product "ReplicationEngine"
to the product "FoodReplicator".

Important: You must make sure the milestones and versions of the bugs in the
component are available in the new product. See syncmsandversions.pl.

Pass in a true value for "doit" to make the database changes permament.
USAGE

    exit(1);
}

#############################################################################
# MAIN CODE
#############################################################################

# This is a pure command line script.
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 3) {
    usage();
    exit();
}

my ($oldproduct, $newproduct, $component, $doit) = @ARGV;

my $dbh = Bugzilla->dbh;

$dbh->{'AutoCommit'} = 0 unless $doit; # Turn off autocommit by default

# Find product IDs
my $oldprodid = $dbh->selectrow_array("SELECT id FROM products WHERE name = ?",
                                      undef, $oldproduct);
if (!$oldprodid) {
    print "Can't find product ID for '$oldproduct'.\n";
    exit(1);
}

my $newprodid = $dbh->selectrow_array("SELECT id FROM products WHERE name = ?",
                                      undef, $newproduct);
if (!$newprodid) {
    print "Can't find product ID for '$newproduct'.\n";
    exit(1);
}

# Find component ID
my $compid = $dbh->selectrow_array("SELECT id FROM components 
                                    WHERE name = ? AND product_id = ?",
                                   undef, $component, $oldprodid);
if (!$compid) {
    print "Can't find component ID for '$component' in product " .            
          "'$oldproduct'.\n";
    exit(1);
}

my $fieldid = $dbh->selectrow_array("SELECT id FROM fielddefs 
                                     WHERE name = 'product'");
if (!$fieldid) {
    print "Can't find field ID for 'product' field!\n";
    exit(1);
}

# check versions
my @missing_versions;
my $ra_versions = $dbh->selectcol_arrayref(
    "SELECT DISTINCT version FROM bugs WHERE component_id = ?",
    undef, $compid);
foreach my $version (@$ra_versions) {
    my $has_version = $dbh->selectrow_array(
        "SELECT 1 FROM versions WHERE product_id = ? AND value = ?",
        undef, $newprodid, $version);
    push @missing_versions, $version unless $has_version;
}

# check milestones
my @missing_milestones;
my $ra_milestones = $dbh->selectcol_arrayref(
    "SELECT DISTINCT target_milestone FROM bugs WHERE component_id = ?",
    undef, $compid);
foreach my $milestone (@$ra_milestones) {
    my $has_milestone = $dbh->selectrow_array(
        "SELECT 1 FROM milestones WHERE product_id=? AND value=?",
        undef, $newprodid, $milestone);
    push @missing_milestones, $milestone unless $has_milestone;
}

my $missing_error = '';
if (@missing_versions) {
    $missing_error .= "'$newproduct' is missing the following version(s):\n  " .
        join("\n  ", @missing_versions) . "\n";
}
if (@missing_milestones) {
    $missing_error .= "'$newproduct' is missing the following milestone(s):\n  " .
        join("\n  ", @missing_milestones) . "\n";
}
die $missing_error if $missing_error;

# confirmation
print <<EOF;
About to move the component '$component'
From '$oldproduct'
To '$newproduct'

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

print "Moving '$component' from '$oldproduct' to '$newproduct'...\n\n";
$dbh->bz_start_transaction() if $doit;

my $ra_ids = $dbh->selectcol_arrayref(
    "SELECT bug_id FROM bugs WHERE product_id=? AND component_id=?",
    undef, $oldprodid, $compid);

# Bugs table
$dbh->do("UPDATE bugs SET product_id = ? WHERE component_id = ?", 
         undef,
         ($newprodid, $compid));

# Flags tables
$dbh->do("UPDATE flaginclusions SET product_id = ? WHERE component_id = ?", 
         undef,
         ($newprodid, $compid));

$dbh->do("UPDATE flagexclusions SET product_id = ? WHERE component_id = ?", 
         undef,
         ($newprodid, $compid));

# Components
$dbh->do("UPDATE components SET product_id = ? WHERE id = ?", 
         undef,
         ($newprodid, $compid));

# Mark bugs as touched
$dbh->do("UPDATE bugs SET delta_ts = NOW() 
          WHERE component_id = ?", undef, $compid);
$dbh->do("UPDATE bugs SET lastdiffed = NOW() 
          WHERE component_id = ?", undef, $compid);

# Update bugs_activity
my $userid = 1; # nobody@mozilla.org

$dbh->do("INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed,
                                    added) 
             SELECT bug_id, ?, delta_ts, ?, ?, ? 
             FROM bugs WHERE component_id = ?",
         undef,
         ($userid, $fieldid, $oldproduct, $newproduct, $compid));

Bugzilla::Hook::process('reorg_move_bugs', { bug_ids => $ra_ids } ) if $doit;
$dbh->bz_commit_transaction() if $doit;
