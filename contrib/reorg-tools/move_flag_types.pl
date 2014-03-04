#!/usr/bin/perl 
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
# 
# Software distributed under the License is distributed on an "AS
# IS" basis,  WITHOUT WARRANTY OF ANY KIND,  either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
# 
# The Initial Developer of the Original Code is Mozilla Foundation 
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
#===============================================================================
#
#         FILE:  move_flag_types.pl
#
#        USAGE:  ./move_flag_types.pl  
#
#  DESCRIPTION:  Move current set flag from one type_id to another
#                based on product and optionally component.
#
#      OPTIONS:  ---
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  David Lawrence (:dkl), dkl@mozilla.com
#      COMPANY:  Mozilla Foundation
#      VERSION:  1.0
#      CREATED:  08/22/2011 05:18:06 PM
#     REVISION:  ---
#===============================================================================

=head1 NAME

move_flag_types.pl - Move currently set flags from one type id to another based
on product and optionally component.

=head1 SYNOPSIS

This script will move bugs matching a specific product (and optionally a component)
from one flag type id to another if the bug has the flag set to either +, -, or ?.

./move_flag_types.pl --old-id 4 --new-id 720 --product Firefox --component Installer

=head1 OPTIONS

=over

=item B<--help|-h|?>

Print a brief help message and exits.

=item B<--oldid|-o>

Old flag type id. Use editflagtypes.cgi to determine the type id from the URL.

=item B<--newid|-n>

New flag type id. Use editflagtypes.cgi to determine the type id from the URL.

=item B<--product|-p> 

The product that the bugs most be assigned to.

=item B<--component|-c>

Optional: The component of the given product that the bugs must be assigned to.

=item B<--doit|-d>

Without this argument, changes are not actually committed to the database.

=back

=cut

use strict;
use warnings;

use lib '.';

use Bugzilla;
use Getopt::Long;
use Pod::Usage;

my %params;
GetOptions(\%params, 'help|h|?', 'oldid|o=s', 'newid|n=s',
                     'product|p=s', 'component|c:s', 'doit|d') or pod2usage(1);

if ($params{'help'} || !$params{'oldid'}
    || !$params{'newid'} || !$params{'product'}) {
    pod2usage({ -message => "Missing required argument", 
                -exitval => 1 });
}

# Set defaults
$params{'doit'} ||= 0;
$params{'component'} ||= '';

my $dbh = Bugzilla->dbh;

# Get the flag names
my $old_flag_name = $dbh->selectrow_array(
    "SELECT name FROM flagtypes WHERE id = ?", 
    undef,  $params{'oldid'});
my $new_flag_name = $dbh->selectrow_array(
    "SELECT name FROM flagtypes WHERE id = ?",   
    undef,   $params{'newid'});

# Find the product id
my $product_id = $dbh->selectrow_array(
    "SELECT id FROM products WHERE name = ?", 
    undef, $params{'product'});

# Find the component id if not __ANY__
my $component_id;
if ($params{'component'}) {
    $component_id = $dbh->selectrow_array(
        "SELECT id FROM components WHERE name = ? AND product_id = ?", 
        undef, $params{'component'}, $product_id);
}

my @query_args = ($params{'oldid'});

my $flag_query = "SELECT flags.id AS flag_id, flags.bug_id AS bug_id
                    FROM flags JOIN bugs ON flags.bug_id = bugs.bug_id 
                   WHERE flags.type_id = ? ";

if ($component_id) {
    # No need to compare against product_id as component_id is already
    # tied to a specific product
    $flag_query .= "AND bugs.component_id = ?";
    push(@query_args, $component_id);
}
else {
    # All bugs for a product regardless of component
    $flag_query .= "AND bugs.product_id = ?";
    push(@query_args, $product_id);
}

my $flags = $dbh->selectall_arrayref($flag_query, undef, @query_args);

if (@$flags) {
    print "Moving '" . scalar @$flags . "' flags " . 
          "from $old_flag_name (" . $params{'oldid'} . ") " .
          "to $new_flag_name (" . $params{'newid'} . ")...\n";

    if (!$params{'doit'}) {
        print "Pass the argument --doit or -d to permanently make changes to the database.\n";
    }  
    else {
        my $flag_update_sth = $dbh->prepare("UPDATE flags SET type_id = ? WHERE id = ?");

        foreach my $flag (@$flags) {
            my ($flag_id, $bug_id) = @$flag;
            print "Bug: $bug_id Flag: $flag_id\n";
            $flag_update_sth->execute($params{'newid'}, $flag_id);
        }
    }

    # It's complex to determine which items now need to be flushed from memcached.
    # As this is expected to be a rare event, we just flush the entire cache.
    Bugzilla->memcached->clear_all();
}
else {
    print "No flags to move\n";
}
