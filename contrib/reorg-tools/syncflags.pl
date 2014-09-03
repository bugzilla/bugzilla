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
Usage: syncflags.pl <srcproduct> <tgtproduct>

E.g.: syncflags.pl FoodReplicator SeaMonkey
will copy any flag inclusions (only) for the product "FoodReplicator"
so matching inclusions exist for the product "SeaMonkey". This script is 
normally used prior to moving components from srcproduct to tgtproduct.
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

$dbh->do("INSERT INTO flaginclusions(component_id, type_id, product_id) 
               SELECT fi1.component_id, fi1.type_id, ? FROM flaginclusions fi1 
            LEFT JOIN flaginclusions fi2 
                      ON fi1.type_id = fi2.type_id
                      AND fi2.product_id = ? 
                WHERE fi1.product_id = ? 
                      AND fi2.type_id IS NULL",
        undef,
        $tgtprodid, $tgtprodid, $srcprodid);

# It's complex to determine which items now need to be flushed from memcached.
# As this is expected to be a rare event, we just flush the entire cache.
Bugzilla->memcached->clear_all();
