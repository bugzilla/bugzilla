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
# Contributor(s): Terry Weissman <terry@mozilla.org>
#                 Andreas Franke <afranke@mathweb.org>
#                 Christian Reis <kiko@async.com.br>
#                 Myk Melez <myk@mozilla.org>
#                 Frédéric Buclin <LpSolit@gmail.com>

use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Bug;

use List::Util qw(max);

my $user = Bugzilla->login();

my $cgi = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars = {};
# Connect to the shadow database if this installation is using one to improve
# performance.
my $dbh = Bugzilla->switch_to_shadow_db();

################################################################################
# Data/Security Validation                                                     #
################################################################################

# Make sure the bug ID is a positive integer representing an existing
# bug that the user is authorized to access.
my $bug = Bugzilla::Bug->check(scalar $cgi->param('id'));
my $id = $bug->id;

local our $hide_resolved = $cgi->param('hide_resolved') ? 1 : 0;
local our $maxdepth = $cgi->param('maxdepth') || 0;
if ($maxdepth !~ /^\d+$/) {
    $maxdepth = 0;
}

################################################################################
# Main Section                                                                 #
################################################################################

# Stores the greatest depth to which either tree goes.
local our $realdepth = 0;

# Generate the tree of bugs that this bug depends on and a list of IDs
# appearing in the tree.
my $dependson_tree = { $id => $bug };
my $dependson_ids = {};
GenerateTree($id, "dependson", 1, $dependson_tree, $dependson_ids);
$vars->{'dependson_tree'} = $dependson_tree;
$vars->{'dependson_ids'}  = [keys(%$dependson_ids)];

# Generate the tree of bugs that this bug blocks and a list of IDs
# appearing in the tree.
my $blocked_tree = { $id => $bug };
my $blocked_ids = {};
GenerateTree($id, "blocked", 1, $blocked_tree, $blocked_ids);
$vars->{'blocked_tree'} = $blocked_tree;
$vars->{'blocked_ids'}  = [keys(%$blocked_ids)];

$vars->{'bugid'}         = $id;
$vars->{'realdepth'}     = $realdepth;
$vars->{'maxdepth'}      = $maxdepth;
$vars->{'hide_resolved'} = $hide_resolved;

print $cgi->header();
$template->process("bug/dependency-tree.html.tmpl", $vars)
  || ThrowTemplateError($template->error());

# Tree Generation Functions

sub GenerateTree {
    my ($bug_id, $relationship, $depth, $bugs, $ids) = @_;

    # determine just the list of bug ids
    _generate_bug_ids($bug_id, $relationship, $depth, $ids);
    my $bug_ids = [ keys %$ids ];
    return unless @$bug_ids;

    # load all the bugs at once
    foreach my $bug (@{ Bugzilla::Bug->new_from_list($bug_ids) }) {
        if (!$bug->{error}) {
            $bugs->{$bug->id} = $bug;
        }
    }

    # preload bug visibility
    Bugzilla->user->visible_bugs($bug_ids);

    # and generate the tree
    _generate_tree($bug_id, $relationship, $depth, $bugs, $ids);
}

sub _generate_bug_ids {
    my ($bug_id, $relationship, $depth, $ids) = @_;

    # Record this depth in the global $realdepth variable if it's farther
    # than we've gone before.
    $realdepth = max($realdepth, $depth);

    my $dependencies = _get_dependencies($bug_id, $relationship);
    foreach my $dep_id (@$dependencies) {
        if (!$maxdepth || $depth <= $maxdepth) {
            $ids->{$dep_id} = 1;
            _generate_bug_ids($dep_id, $relationship, $depth + 1, $ids);
        }
    }
}

sub _generate_tree {
    my ($bug_id, $relationship, $depth, $bugs, $ids) = @_;

    my $dependencies = _get_dependencies($bug_id, $relationship);

    foreach my $dep_id (@$dependencies) {
        # recurse
        if (!$maxdepth || $depth < $maxdepth) {
            _generate_tree($dep_id, $relationship, $depth + 1, $bugs, $ids);
        }

        # remove bugs according to visiblity and filters
        if (!Bugzilla->user->can_see_bug($dep_id)
            || ($hide_resolved && !$bugs->{$dep_id}->isopened))
        {
            delete $ids->{$dep_id};
        }
        elsif (!grep { $_ == $dep_id } @{ $bugs->{dependencies}->{$bug_id} }) {
            push @{ $bugs->{dependencies}->{$bug_id} }, $dep_id;
        }
    }
}

sub _get_dependencies {
    my ($bug_id, $relationship) = @_;
    my $cache = Bugzilla->request_cache->{dependency_cache} ||= {};
    return $cache->{$bug_id}->{$relationship} ||=
        $relationship eq 'dependson'
        ? Bugzilla::Bug::EmitDependList('blocked',   'dependson', $bug_id)
        : Bugzilla::Bug::EmitDependList('dependson', 'blocked',   $bug_id);
}

