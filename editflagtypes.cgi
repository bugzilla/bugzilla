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
# Contributor(s): Myk Melez <myk@mozilla.org>
#                 Frédéric Buclin <LpSolit@gmail.com>

################################################################################
# Script Initialization
################################################################################

# Make it harder for us to do dangerous things in Perl.
use strict;
use lib qw(. lib);

# Use Bugzilla's flag modules for handling flag types.
use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Flag;
use Bugzilla::FlagType;
use Bugzilla::Group;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Product;
use Bugzilla::Component;
use Bugzilla::Token;

# Make sure the user is logged in and has the right privileges.
my $user = Bugzilla->login(LOGIN_REQUIRED);
my $cgi = Bugzilla->cgi;
my $template = Bugzilla->template;

# We need this everywhere.
my $vars = get_products_and_components();

print $cgi->header();

$user->in_group('editcomponents')
  || ThrowUserError("auth_failure", {group  => "editcomponents",
                                     action => "edit",
                                     object => "flagtypes"});

my $action = $cgi->param('action') || 'list';
my $token  = $cgi->param('token');
my $product = $cgi->param('product');
my $component = $cgi->param('component');
my $flag_id = $cgi->param('id');

if ($product) {
    $product = Bugzilla::Product->check({ name => $product, allow_inaccessible => 1 });
}

if ($component) {
    ($product && $product->id)
      || ThrowUserError('flag_type_component_without_product');
    $component = Bugzilla::Component->check({ product => $product, name => $component });
}

# If 'categoryAction' is set, it has priority over 'action'.
if (my ($category_action) = grep { $_ =~ /^categoryAction-(?:\w+)$/ } $cgi->param()) {
    $category_action =~ s/^categoryAction-//;

    my @inclusions = $cgi->param('inclusions');
    my @exclusions = $cgi->param('exclusions');
    if ($category_action eq 'include') {
        my $category = ($product ? $product->id : 0) . ":" .
                       ($component ? $component->id : 0);
        push(@inclusions, $category) unless grep($_ eq $category, @inclusions);
    }
    elsif ($category_action eq 'exclude') {
        my $category = ($product ? $product->id : 0) . ":" .
                       ($component ? $component->id : 0);
        push(@exclusions, $category) unless grep($_ eq $category, @exclusions);
    }
    elsif ($category_action eq 'removeInclusion') {
        my @inclusion_to_remove = $cgi->param('inclusion_to_remove');
        foreach my $remove (@inclusion_to_remove) {
            @inclusions = grep { $_ ne $remove } @inclusions;
        }
    }
    elsif ($category_action eq 'removeExclusion') {
        my @exclusion_to_remove = $cgi->param('exclusion_to_remove');
        foreach my $remove (@exclusion_to_remove) {
            @exclusions = grep { $_ ne $remove } @exclusions;
        }
    }

    # Convert the array @clusions('prod_ID:comp_ID') back to a hash of
    # the form %clusions{'prod_name:comp_name'} = 'prod_ID:comp_ID'
    my %inclusions = clusion_array_to_hash(\@inclusions);
    my %exclusions = clusion_array_to_hash(\@exclusions);

    $vars->{'groups'} = [Bugzilla::Group->get_all];
    $vars->{'action'} = $action;

    my $type = {};
    $type->{$_} = $cgi->param($_) foreach $cgi->param();
    # Make sure boolean fields are defined, else they fall back to 1.
    foreach my $boolean qw(is_active is_requestable is_requesteeble is_multiplicable) {
        $type->{$boolean} ||= 0;
    }

    # That's what I call a big hack. The template expects to see a group object.
    $type->{'grant_group'} = {};
    $type->{'grant_group'}->{'name'} = $cgi->param('grant_group');
    $type->{'request_group'} = {};
    $type->{'request_group'}->{'name'} = $cgi->param('request_group');

    $type->{'inclusions'} = \%inclusions;
    $type->{'exclusions'} = \%exclusions;
    $vars->{'type'} = $type;
    $vars->{'token'} = $token;

    $template->process("admin/flag-type/edit.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if ($action eq 'list') {
    my $product_id = $product ? $product->id : 0;
    my $component_id = $component ? $component->id : 0;
    my $show_flag_counts = $cgi->param('show_flag_counts') ? 1 : 0;
    my $group_id = $cgi->param('group');

    my $bug_flagtypes;
    my $attach_flagtypes;

    # If a component is given, restrict the list to flag types available
    # for this component.
    if ($component) {
        $bug_flagtypes = $component->flag_types->{'bug'};
        $attach_flagtypes = $component->flag_types->{'attachment'};

        # Filter flag types if a group ID is given.
        $bug_flagtypes = filter_group($bug_flagtypes, $group_id);
        $attach_flagtypes = filter_group($attach_flagtypes, $group_id);

    }
    # If only a product is specified but no component, then restrict the list
    # to flag types available in at least one component of that product.
    elsif ($product) {
        $bug_flagtypes = $product->flag_types->{'bug'};
        $attach_flagtypes = $product->flag_types->{'attachment'};

        # Filter flag types if a group ID is given.
        $bug_flagtypes = filter_group($bug_flagtypes, $group_id);
        $attach_flagtypes = filter_group($attach_flagtypes, $group_id);
    }
    # If no product is given, then show all flag types available.
    else {
        my $flagtypes = Bugzilla::FlagType::match({ group => $group_id });

        $bug_flagtypes = [grep { $_->target_type eq 'bug' } @$flagtypes];
        $attach_flagtypes = [grep { $_->target_type eq 'attachment' } @$flagtypes];
    }

    if ($show_flag_counts) {
        my %bug_lists;
        my %map = ('+' => 'granted', '-' => 'denied', '?' => 'pending');

        foreach my $flagtype (@$bug_flagtypes, @$attach_flagtypes) {
            $bug_lists{$flagtype->id} = {};
            my $flags = Bugzilla::Flag->match({type_id => $flagtype->id});
            # Build lists of bugs, triaged by flag status.
            push(@{$bug_lists{$flagtype->id}->{$map{$_->status}}}, $_->bug_id) foreach @$flags;
        }
        $vars->{'bug_lists'} = \%bug_lists;
        $vars->{'show_flag_counts'} = 1;
    }

    $vars->{'selected_product'} = $product ? $product->name : '';
    $vars->{'selected_component'} = $component ? $component->name : '';
    $vars->{'bug_types'} = $bug_flagtypes;
    $vars->{'attachment_types'} = $attach_flagtypes;

    $template->process("admin/flag-type/list.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if ($action eq 'enter') {
    my $type = $cgi->param('target_type');
    ($type eq 'bug' || $type eq 'attachment')
      || ThrowCodeError('flag_type_target_type_invalid', { target_type => $type });

    $vars->{'action'} = 'insert';
    $vars->{'token'} = issue_session_token('add_flagtype');
    $vars->{'type'} = { 'target_type' => $type,
                        'inclusions'  => { '__Any__:__Any__' => '0:0' } };
    # Get a list of groups available to restrict this flag type against.
    $vars->{'groups'} = [Bugzilla::Group->get_all];

    $template->process("admin/flag-type/edit.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if ($action eq 'edit' || $action eq 'copy') {
    $vars->{'type'} = Bugzilla::FlagType->check({ id => $flag_id });

    if ($action eq 'copy') {
        $vars->{'action'} = "insert";
        $vars->{'token'} = issue_session_token('add_flagtype');
    }
    else { 
        $vars->{'action'} = "update";
        $vars->{'token'} = issue_session_token('edit_flagtype');
    }

    # Get a list of groups available to restrict this flag type against.
    $vars->{'groups'} = [Bugzilla::Group->get_all];

    $template->process("admin/flag-type/edit.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if ($action eq 'insert') {
    check_token_data($token, 'add_flagtype');

    my $name             = $cgi->param('name');
    my $description      = $cgi->param('description');
    my $target_type      = $cgi->param('target_type');
    my $cc_list          = $cgi->param('cc_list');
    my $sortkey          = $cgi->param('sortkey');
    my $is_active        = $cgi->param('is_active');
    my $is_requestable   = $cgi->param('is_requestable');
    my $is_specifically  = $cgi->param('is_requesteeble');
    my $is_multiplicable = $cgi->param('is_multiplicable');
    my $grant_group      = $cgi->param('grant_group');
    my $request_group    = $cgi->param('request_group');
    my @inclusions       = $cgi->param('inclusions');
    my @exclusions       = $cgi->param('exclusions');

    my $flagtype = Bugzilla::FlagType->create({
        name        => $name,
        description => $description,
        target_type => $target_type,
        cc_list     => $cc_list,
        sortkey     => $sortkey,
        is_active   => $is_active,
        is_requestable   => $is_requestable,
        is_requesteeble  => $is_specifically,
        is_multiplicable => $is_multiplicable,
        grant_group      => $grant_group,
        request_group    => $request_group,
        inclusions       => \@inclusions,
        exclusions       => \@exclusions
    });

    delete_token($token);

    $vars->{'name'} = $flagtype->name;
    $vars->{'message'} = "flag_type_created";

    my @flagtypes = Bugzilla::FlagType->get_all;
    $vars->{'bug_types'} = [grep { $_->target_type eq 'bug' } @flagtypes];
    $vars->{'attachment_types'} = [grep { $_->target_type eq 'attachment' } @flagtypes];

    $template->process("admin/flag-type/list.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if ($action eq 'update') {
    check_token_data($token, 'edit_flagtype');

    my $name             = $cgi->param('name');
    my $description      = $cgi->param('description');
    my $cc_list          = $cgi->param('cc_list');
    my $sortkey          = $cgi->param('sortkey');
    my $is_active        = $cgi->param('is_active');
    my $is_requestable   = $cgi->param('is_requestable');
    my $is_specifically  = $cgi->param('is_requesteeble');
    my $is_multiplicable = $cgi->param('is_multiplicable');
    my $grant_group      = $cgi->param('grant_group');
    my $request_group    = $cgi->param('request_group');
    my @inclusions       = $cgi->param('inclusions');
    my @exclusions       = $cgi->param('exclusions');

    my $flagtype = Bugzilla::FlagType->check({ id => $flag_id });
    $flagtype->set_name($name);
    $flagtype->set_description($description);
    $flagtype->set_cc_list($cc_list);
    $flagtype->set_sortkey($sortkey);
    $flagtype->set_is_active($is_active);
    $flagtype->set_is_requestable($is_requestable);
    $flagtype->set_is_specifically_requestable($is_specifically);
    $flagtype->set_is_multiplicable($is_multiplicable);
    $flagtype->set_grant_group($grant_group);
    $flagtype->set_request_group($request_group);
    $flagtype->set_clusions({ inclusions => \@inclusions, exclusions => \@exclusions});
    $flagtype->update();

    delete_token($token);

    $vars->{'name'} = $flagtype->name;
    $vars->{'message'} = "flag_type_changes_saved";

    my @flagtypes = Bugzilla::FlagType->get_all;
    $vars->{'bug_types'} = [grep { $_->target_type eq 'bug' } @flagtypes];
    $vars->{'attachment_types'} = [grep { $_->target_type eq 'attachment' } @flagtypes];

    $template->process("admin/flag-type/list.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if ($action eq 'confirmdelete') {
    $vars->{'flag_type'} = Bugzilla::FlagType->check({ id => $flag_id });
    $vars->{'token'} = issue_session_token('delete_flagtype');

    $template->process("admin/flag-type/confirm-delete.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if ($action eq 'delete') {
    check_token_data($token, 'delete_flagtype');

    my $flagtype = Bugzilla::FlagType->check({ id => $flag_id });
    $flagtype->remove_from_db();

    delete_token($token);

    $vars->{'name'} = $flagtype->name;
    $vars->{'message'} = "flag_type_deleted";

    my @flagtypes = Bugzilla::FlagType->get_all;
    $vars->{'bug_types'} = [grep { $_->target_type eq 'bug' } @flagtypes];
    $vars->{'attachment_types'} = [grep { $_->target_type eq 'attachment' } @flagtypes];

    $template->process("admin/flag-type/list.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if ($action eq 'deactivate') {
    check_token_data($token, 'delete_flagtype');

    my $flagtype = Bugzilla::FlagType->check({ id => $flag_id });
    $flagtype->set_is_active(0);
    $flagtype->update();

    delete_token($token);

    $vars->{'message'} = "flag_type_deactivated";
    $vars->{'flag_type'} = $flagtype;

    my @flagtypes = Bugzilla::FlagType->get_all;
    $vars->{'bug_types'} = [grep { $_->target_type eq 'bug' } @flagtypes];
    $vars->{'attachment_types'} = [grep { $_->target_type eq 'attachment' } @flagtypes];

    $template->process("admin/flag-type/list.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

ThrowUserError('unknown_action', {action => $action});

#####################
# Helper subroutines
#####################

sub get_products_and_components {
    my $vars = {};

    my @products = Bugzilla::Product->get_all;
    # We require all unique component names.
    my %components;
    foreach my $product (@products) {
        foreach my $component (@{$product->components}) {
            $components{$component->name} = 1;
        }
    }
    $vars->{'products'} = \@products;
    $vars->{'components'} = [sort(keys %components)];
    return $vars;
}

sub filter_group {
    my ($flag_types, $gid) = @_;
    return $flag_types unless $gid;

    my @flag_types = grep {($_->grant_group && $_->grant_group->id == $gid)
                           || ($_->request_group && $_->request_group->id == $gid)} @$flag_types;

    return \@flag_types;
}

# Convert the array @clusions('prod_ID:comp_ID') back to a hash of
# the form %clusions{'prod_name:comp_name'} = 'prod_ID:comp_ID'
sub clusion_array_to_hash {
    my $array = shift;
    my %hash;
    my %products;
    my %components;
    foreach my $ids (@$array) {
        trick_taint($ids);
        my ($product_id, $component_id) = split(":", $ids);
        my $product_name = "__Any__";
        if ($product_id) {
            $products{$product_id} ||= new Bugzilla::Product($product_id);
            $product_name = $products{$product_id}->name if $products{$product_id};
        }
        my $component_name = "__Any__";
        if ($component_id) {
            $components{$component_id} ||= new Bugzilla::Component($component_id);
            $component_name = $components{$component_id}->name if $components{$component_id};
        }
        $hash{"$product_name:$component_name"} = $ids;
    }
    return %hash;
}
