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

use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;

sub usage() {
    print <<USAGE;
Usage: syncmsandversions.pl <srcproduct> <tgtproduct>

E.g.: syncmsandversions.pl FoodReplicator SeaMonkey
will copy any versions and milstones in the product "FoodReplicator"
which do not exist in product "SeaMonkey" into it. This script is normally
used prior to moving components from srcproduct to tgtproduct.
USAGE

    exit(1);
}

#############################################################################
# MAIN CODE
#############################################################################

# This is a pure command line script.
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 2) {
    usage();
    exit();
}

my ($srcproduct, $tgtproduct) = @ARGV;

my $dbh = Bugzilla->dbh;

# Find product IDs
my $srcprodid = $dbh->selectrow_array("SELECT id FROM products WHERE name = ?",
                                      undef, $srcproduct);
if (!$srcprodid) {
    print "Can't find product ID for '$srcproduct'.\n";
    exit(1);
}

my $tgtprodid = $dbh->selectrow_array("SELECT id FROM products WHERE name = ?",
                                      undef, $tgtproduct);
if (!$tgtprodid) {
    print "Can't find product ID for '$tgtproduct'.\n";
    exit(1);
}

$dbh->bz_start_transaction();

$dbh->do("
    INSERT INTO milestones(value, sortkey, isactive, product_id)
        SELECT m1.value, m1.sortkey, m1.isactive, ?
          FROM milestones m1
               LEFT JOIN milestones m2 ON m1.value = m2.value
                                          AND m2.product_id = ?
         WHERE m1.product_id = ?
               AND m2.value IS NULL
    ",
    undef,
    $tgtprodid, $tgtprodid, $srcprodid);

$dbh->do("
    INSERT INTO versions(value, isactive, product_id)
        SELECT v1.value, v1.isactive, ?
          FROM versions v1
               LEFT JOIN versions v2 ON v1.value = v2.value
                                     AND v2.product_id = ?
         WHERE v1.product_id = ?
               AND v2.value IS NULL
    ",
    undef,
    $tgtprodid, $tgtprodid, $srcprodid);

$dbh->do("
    INSERT INTO group_control_map (group_id, product_id, entry, membercontrol,
                                   othercontrol, canedit, editcomponents,
                                   editbugs, canconfirm)
        SELECT g1.group_id, ?, g1.entry, g1.membercontrol, g1.othercontrol,
               g1.canedit, g1.editcomponents, g1.editbugs, g1.canconfirm
          FROM group_control_map g1
               LEFT JOIN group_control_map g2 ON g1.product_id = ?
                                                 AND g2.product_id = ?
                                                 AND g1.group_id = g2.group_id
         WHERE g1.product_id = ?
               AND g2.group_id IS NULL
    ",
    undef,
    $tgtprodid, $srcprodid, $tgtprodid, $srcprodid);

$dbh->bz_commit_transaction();

exit(0);

