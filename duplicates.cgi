#!/usr/bin/perl -wT
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
# Contributor(s): 
#   Gervase Markham <gerv@gerv.net>
#   Max Kanat-Alexander <mkanat@bugzilla.org>

use strict;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Search;
use Bugzilla::Field;
use Bugzilla::Product;

###############
# Subroutines #
###############

# $counts is a count of exactly how many direct duplicates there are for
# each bug we're considering. $dups is a map of duplicates, from one
# bug_id to another. We go through the duplicates map ($dups) and if one bug
# in $count is a duplicate of another bug in $count, we add their counts
# together under the target bug.
sub add_indirect_dups {
    my ($counts, $dups) = @_;

    foreach my $add_from (keys %$dups) {
        my $add_to     = walk_dup_chain($dups, $add_from);
        my $add_amount = delete $counts->{$add_from} || 0;
        $counts->{$add_to} += $add_amount;
    }
}

sub walk_dup_chain {
    my ($dups, $from_id) = @_;
    my $to_id = $dups->{$from_id};
    while (my $bug_id = $dups->{$to_id}) {
        last if $bug_id == $from_id; # avoid duplicate loops
        $to_id = $bug_id;
    }
    # Optimize for future calls to add_indirect_dups.
    $dups->{$from_id} = $to_id;
    return $to_id;
}

###############
# Main Script #
###############

my $cgi = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars = {};

Bugzilla->login();

my $dbh = Bugzilla->switch_to_shadow_db();

# Get params from URL
sub formvalue {
    my ($name, $default) = (@_);
    return Bugzilla->cgi->param($name) || $default || "";
}

my $sortby = formvalue("sortby");
my $changedsince = formvalue("changedsince", 7);
my $maxrows = formvalue("maxrows", 100);
my $openonly = formvalue("openonly");
my $reverse = formvalue("reverse") ? 1 : 0;
my @query_products = $cgi->param('product');
my $sortvisible = formvalue("sortvisible");
my @buglist = (split(/[:,]/, formvalue("bug_id")));
detaint_natural($_) foreach @buglist;
# If we got any non-numeric items, they will now be undef. Remove them from
# the list.
@buglist = grep($_, @buglist);

# Make sure all products are valid.
foreach my $p (@query_products) {
    Bugzilla::Product::check_product($p);
}

# Small backwards-compatibility hack, dated 2002-04-10.
$sortby = "count" if $sortby eq "dup_count";

my $origmaxrows = $maxrows;
detaint_natural($maxrows)
  || ThrowUserError("invalid_maxrows", { maxrows => $origmaxrows});

my $origchangedsince = $changedsince;
detaint_natural($changedsince)
  || ThrowUserError("invalid_changedsince", 
                    { changedsince => $origchangedsince });


my %total_dups = @{$dbh->selectcol_arrayref(
    "SELECT dupe_of, COUNT(dupe)
       FROM duplicates
   GROUP BY dupe_of", {Columns => [1,2]})};

my %dupe_relation = @{$dbh->selectcol_arrayref(
    "SELECT dupe, dupe_of FROM duplicates
      WHERE dupe IN (SELECT dupe_of FROM duplicates)",
    {Columns => [1,2]})};
add_indirect_dups(\%total_dups, \%dupe_relation);

my $reso_field_id = get_field_id('resolution');
my %since_dups = @{$dbh->selectcol_arrayref(
    "SELECT dupe_of, COUNT(dupe)
       FROM duplicates INNER JOIN bugs_activity 
                       ON bugs_activity.bug_id = duplicates.dupe 
      WHERE added = 'DUPLICATE' AND fieldid = ? AND " 
            . $dbh->sql_to_days('bug_when') . " >= (" 
            . $dbh->sql_to_days('NOW()') . " - ?)
   GROUP BY dupe_of", {Columns=>[1,2]},
    $reso_field_id, $changedsince)};
add_indirect_dups(\%since_dups, \%dupe_relation);

my (@bugs, @bug_ids);

foreach my $id (keys %total_dups) {
    if ($total_dups{$id} < Bugzilla->params->{'mostfreqthreshold'}) {
        delete $total_dups{$id};
        next;
    }
    if ($sortvisible and @buglist and !grep($_ == $id, @buglist)) {
        delete $total_dups{$id};
    }
}

if (scalar %total_dups) {
    # use Bugzilla::Search so that we get the security checking
    my $params = new Bugzilla::CGI({ 'bug_id' => [keys %total_dups] });

    if ($openonly) {
        $params->param('resolution', '---');
    } else {
        # We want to show bugs which:
        # a) Aren't CLOSED; and
        # b)  i) Aren't VERIFIED; OR
        #    ii) Were resolved INVALID/WONTFIX

        # The rationale behind this is that people will eventually stop
        # reporting fixed bugs when they get newer versions of the software,
        # but if the bug is determined to be erroneous, people will still
        # keep reporting it, so we do need to show it here.

        # a)
        $params->param('field0-0-0', 'bug_status');
        $params->param('type0-0-0', 'notequals');
        $params->param('value0-0-0', 'CLOSED');

        # b) i)
        $params->param('field0-1-0', 'bug_status');
        $params->param('type0-1-0', 'notequals');
        $params->param('value0-1-0', 'VERIFIED');

        # b) ii)
        $params->param('field0-1-1', 'resolution');
        $params->param('type0-1-1', 'anyexact');
        $params->param('value0-1-1', 'INVALID,WONTFIX');
    }

    # Restrict to product if requested
    if ($cgi->param('product')) {
        $params->param('product', join(',', @query_products));
    }

    my $query = new Bugzilla::Search('fields' => [qw(bug_id
                                                     component
                                                     bug_severity
                                                     op_sys
                                                     target_milestone
                                                     short_desc
                                                     bug_status
                                                     resolution
                                                    )
                                                 ],
                                     'params' => $params,
                                    );

    my $results = $dbh->selectall_arrayref($query->getSQL());

    foreach my $result (@$results) {
        # Note: maximum row count is dealt with in the template.

        my ($id, $component, $bug_severity, $op_sys, $target_milestone, 
            $short_desc, $bug_status, $resolution) = @$result;

        push (@bugs, { id => $id,
                       count => $total_dups{$id},
                       delta => $since_dups{$id} || 0, 
                       component => $component,
                       bug_severity => $bug_severity,
                       op_sys => $op_sys,
                       target_milestone => $target_milestone,
                       short_desc => $short_desc,
                       bug_status => $bug_status, 
                       resolution => $resolution });
        push (@bug_ids, $id); 
    }
}

$vars->{'bugs'} = \@bugs;
$vars->{'bug_ids'} = \@bug_ids;

$vars->{'sortby'} = $sortby;
$vars->{'sortvisible'} = $sortvisible;
$vars->{'changedsince'} = $changedsince;
$vars->{'maxrows'} = $maxrows;
$vars->{'openonly'} = $openonly;
$vars->{'reverse'} = $reverse;
$vars->{'format'} = $cgi->param('format');
$vars->{'query_products'} = \@query_products;
$vars->{'products'} = Bugzilla->user->get_selectable_products;


my $format = $template->get_format("reports/duplicates",
                                   scalar($cgi->param('format')),
                                   scalar($cgi->param('ctype')));

# We set the charset in Bugzilla::CGI, but CGI.pm ignores it unless the
# Content-Type is a text type. In some cases, such as when we are
# generating RDF, it isn't, so we specify the charset again here.
print $cgi->header(
    -type => $format->{'ctype'},
    (Bugzilla->params->{'utf8'} ? ('charset', 'utf8') : () )
);

# Generate and return the UI (HTML page) from the appropriate template.
$template->process($format->{'template'}, $vars)
  || ThrowTemplateError($template->error());
