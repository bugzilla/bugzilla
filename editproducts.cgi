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
# The Original Code is mozilla.org code.
#
# The Initial Developer of the Original Code is Holger
# Schurig. Portions created by Holger Schurig are
# Copyright (C) 1999 Holger Schurig. All
# Rights Reserved.
#
# Contributor(s): Holger Schurig <holgerschurig@nikocity.de>
#               Terry Weissman <terry@mozilla.org>
#               Dawn Endico <endico@mozilla.org>
#               Joe Robins <jmrobins@tgix.com>
#               Gavin Shelley <bugzilla@chimpychompy.org>
#               Frédéric Buclin <LpSolit@gmail.com>
#               Greg Hendricks <ghendricks@novell.com>
#               Lance Larsh <lance.larsh@oracle.com>
#               Elliotte Martin <elliotte.martin@yahoo.com>

use strict;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Bug;
use Bugzilla::Product;
use Bugzilla::Classification;
use Bugzilla::Token;

#
# Preliminary checks:
#

my $user = Bugzilla->login(LOGIN_REQUIRED);
my $whoid = $user->id;

my $dbh = Bugzilla->dbh;
my $cgi = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars = {};
# Remove this as soon as the documentation about products has been
# improved and each action has its own section.
$vars->{'doc_section'} = 'products.html';

print $cgi->header();

$user->in_group('editcomponents')
  || scalar(@{$user->get_products_by_permission('editcomponents')})
  || ThrowUserError("auth_failure", {group  => "editcomponents",
                                     action => "edit",
                                     object => "products"});

#
# often used variables
#
my $classification_name = trim($cgi->param('classification') || '');
my $product_name = trim($cgi->param('product') || '');
my $action  = trim($cgi->param('action')  || '');
my $token = $cgi->param('token');

#
# product = '' -> Show nice list of classifications (if
# classifications enabled)
#

if (Bugzilla->params->{'useclassification'} 
    && !$classification_name
    && !$product_name)
{
    $vars->{'classifications'} = $user->get_selectable_classifications;
    
    $template->process("admin/products/list-classifications.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
    exit;
}


#
# action = '' -> Show a nice list of products, unless a product
#                is already specified (then edit it)
#

if (!$action && !$product_name) {
    my $classification;
    my $products;

    if (Bugzilla->params->{'useclassification'}) {
        $classification =
            Bugzilla::Classification::check_classification($classification_name);

        $products = $user->get_selectable_products($classification->id);
        $vars->{'classification'} = $classification;
    } else {
        $products = $user->get_selectable_products;
    }

    # If the user has editcomponents privs for some products only,
    # we have to restrict the list of products to display.
    unless ($user->in_group('editcomponents')) {
        $products = $user->get_products_by_permission('editcomponents');
        if (Bugzilla->params->{'useclassification'}) {
            @$products = grep {$_->classification_id == $classification->id} @$products;
        }
    }
    $vars->{'products'} = $products;
    $vars->{'showbugcounts'} = $cgi->param('showbugcounts') ? 1 : 0;

    $template->process("admin/products/list.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}




#
# action='add' -> present form for parameters for new product
#
# (next action will be 'new')
#

if ($action eq 'add') {
    # The user must have the global editcomponents privs to add
    # new products.
    $user->in_group('editcomponents')
      || ThrowUserError("auth_failure", {group  => "editcomponents",
                                         action => "add",
                                         object => "products"});

    if (Bugzilla->params->{'useclassification'}) {
        my $classification = 
            Bugzilla::Classification::check_classification($classification_name);
        $vars->{'classification'} = $classification;
    }
    $vars->{'token'} = issue_session_token('add_product');

    $template->process("admin/products/create.html.tmpl", $vars)
      || ThrowTemplateError($template->error());

    exit;
}


#
# action='new' -> add product entered in the 'action=add' screen
#

if ($action eq 'new') {
    # The user must have the global editcomponents privs to add
    # new products.
    $user->in_group('editcomponents')
      || ThrowUserError("auth_failure", {group  => "editcomponents",
                                         action => "add",
                                         object => "products"});

    check_token_data($token, 'add_product');

    my $product =
      Bugzilla::Product->create({classification   => $classification_name,
                                 name             => $product_name,
                                 description      => scalar $cgi->param('description'),
                                 version          => scalar $cgi->param('version'),
                                 defaultmilestone => scalar $cgi->param('defaultmilestone'),
                                 milestoneurl     => scalar $cgi->param('milestoneurl'),
                                 disallownew      => scalar $cgi->param('disallownew'),
                                 votesperuser     => scalar $cgi->param('votesperuser'),
                                 maxvotesperbug   => scalar $cgi->param('maxvotesperbug'),
                                 votestoconfirm   => scalar $cgi->param('votestoconfirm'),
                                 create_series    => scalar $cgi->param('createseries')});

    delete_token($token);

    $vars->{'message'} = 'product_created';
    $vars->{'product'} = $product;
    if (Bugzilla->params->{'useclassification'}) {
        $vars->{'classification'} = new Bugzilla::Classification($product->classification_id);
    }
    $vars->{'token'} = issue_session_token('edit_product');

    $template->process("admin/products/edit.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
    exit;
}

#
# action='del' -> ask if user really wants to delete
#
# (next action would be 'delete')
#

if ($action eq 'del') {
    my $product = $user->check_can_admin_product($product_name);

    if (Bugzilla->params->{'useclassification'}) {
        $vars->{'classification'} = new Bugzilla::Classification($product->classification_id);
    }
    $vars->{'product'} = $product;
    $vars->{'token'} = issue_session_token('delete_product');

    $template->process("admin/products/confirm-delete.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
    exit;
}

#
# action='delete' -> really delete the product
#

if ($action eq 'delete') {
    my $product = $user->check_can_admin_product($product_name);
    check_token_data($token, 'delete_product');

    $product->remove_from_db;
    delete_token($token);

    $vars->{'message'} = 'product_deleted';
    $vars->{'product'} = $product;
    $vars->{'no_edit_product_link'} = 1;

    if (Bugzilla->params->{'useclassification'}) {
        $vars->{'classifications'} = $user->get_selectable_classifications;

        $template->process("admin/products/list-classifications.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
    }
    else {
        my $products = $user->get_selectable_products;
        # If the user has editcomponents privs for some products only,
        # we have to restrict the list of products to display.
        unless ($user->in_group('editcomponents')) {
            $products = $user->get_products_by_permission('editcomponents');
        }
        $vars->{'products'} = $products;

        $template->process("admin/products/list.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
    }
    exit;
}

#
# action='edit' -> present the 'edit product' form
# If a product is given with no action associated with it, then edit it.
#
# (next action would be 'update')
#

if ($action eq 'edit' || (!$action && $product_name)) {
    my $product = $user->check_can_admin_product($product_name);

    if (Bugzilla->params->{'useclassification'}) {
        $vars->{'classification'} = new Bugzilla::Classification($product->classification_id);
    }
    $vars->{'product'} = $product;
    $vars->{'token'} = issue_session_token('edit_product');

    $template->process("admin/products/edit.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
    exit;
}

#
# action='updategroupcontrols' -> update the product
#

if ($action eq 'updategroupcontrols') {
    my $product = $user->check_can_admin_product($product_name);
    check_token_data($token, 'edit_group_controls');

    my @now_na = ();
    my @now_mandatory = ();
    foreach my $f ($cgi->param()) {
        if ($f =~ /^membercontrol_(\d+)$/) {
            my $id = $1;
            if ($cgi->param($f) == CONTROLMAPNA) {
                push @now_na,$id;
            } elsif ($cgi->param($f) == CONTROLMAPMANDATORY) {
                push @now_mandatory,$id;
            }
        }
    }
    if (!defined $cgi->param('confirmed')) {
        my $na_groups;
        if (@now_na) {
            $na_groups = $dbh->selectall_arrayref(
                    'SELECT groups.name, COUNT(bugs.bug_id) AS count
                       FROM bugs
                 INNER JOIN bug_group_map
                         ON bug_group_map.bug_id = bugs.bug_id
                 INNER JOIN groups
                         ON bug_group_map.group_id = groups.id
                      WHERE groups.id IN (' . join(', ', @now_na) . ')
                        AND bugs.product_id = ? ' .
                       $dbh->sql_group_by('groups.name'),
                   {'Slice' => {}}, $product->id);
        }

#
# return the mandatory groups which need to have bug entries added to the bug_group_map
# and the corresponding bug count
#
        my $mandatory_groups;
        if (@now_mandatory) {
            $mandatory_groups = $dbh->selectall_arrayref(
                    'SELECT groups.name,
                           (SELECT COUNT(bugs.bug_id)
                              FROM bugs
                             WHERE bugs.product_id = ?
                               AND bugs.bug_id NOT IN
                                (SELECT bug_group_map.bug_id FROM bug_group_map
                                  WHERE bug_group_map.group_id = groups.id))
                           AS count
                      FROM groups
                     WHERE groups.id IN (' . join(', ', @now_mandatory) . ')
                     ORDER BY groups.name',
                   {'Slice' => {}}, $product->id);
            # remove zero counts
            @$mandatory_groups = grep { $_->{count} } @$mandatory_groups;

        }
        if (($na_groups && scalar(@$na_groups))
            || ($mandatory_groups && scalar(@$mandatory_groups)))
        {
            $vars->{'product'} = $product;
            $vars->{'na_groups'} = $na_groups;
            $vars->{'mandatory_groups'} = $mandatory_groups;
            $template->process("admin/products/groupcontrol/confirm-edit.html.tmpl", $vars)
                || ThrowTemplateError($template->error());
            exit;                
        }
    }

    my $groups = $dbh->selectall_arrayref('SELECT id, name FROM groups
                                           WHERE isbuggroup != 0
                                           AND isactive != 0');
    foreach my $group (@$groups) {
        my ($groupid, $groupname) = @$group;
        my $newmembercontrol = $cgi->param("membercontrol_$groupid") || 0;
        my $newothercontrol = $cgi->param("othercontrol_$groupid") || 0;
        #  Legality of control combination is a function of
        #  membercontrol\othercontrol
        #                 NA SH DE MA
        #              NA  +  -  -  -
        #              SH  +  +  +  +
        #              DE  +  -  +  +
        #              MA  -  -  -  +
        unless (($newmembercontrol == $newothercontrol)
              || ($newmembercontrol == CONTROLMAPSHOWN)
              || (($newmembercontrol == CONTROLMAPDEFAULT)
               && ($newothercontrol != CONTROLMAPSHOWN))) {
            ThrowUserError('illegal_group_control_combination',
                            {groupname => $groupname});
        }
    }
    $dbh->bz_start_transaction();

    my $sth_Insert = $dbh->prepare('INSERT INTO group_control_map
                                    (group_id, product_id, entry, membercontrol,
                                     othercontrol, canedit, editcomponents,
                                     canconfirm, editbugs)
                                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)');

    my $sth_Update = $dbh->prepare('UPDATE group_control_map
                                       SET entry = ?, membercontrol = ?,
                                           othercontrol = ?, canedit = ?,
                                           editcomponents = ?, canconfirm = ?,
                                           editbugs = ?
                                     WHERE group_id = ? AND product_id = ?');

    my $sth_Delete = $dbh->prepare('DELETE FROM group_control_map
                                     WHERE group_id = ? AND product_id = ?');

    $groups = $dbh->selectall_arrayref('SELECT id, name, entry, membercontrol,
                                               othercontrol, canedit,
                                               editcomponents, canconfirm, editbugs
                                          FROM groups
                                     LEFT JOIN group_control_map
                                            ON group_control_map.group_id = id
                                           AND product_id = ?
                                         WHERE isbuggroup != 0
                                           AND isactive != 0',
                                         undef, $product->id);

    foreach my $group (@$groups) {
        my ($groupid, $groupname, $entry, $membercontrol, $othercontrol,
            $canedit, $editcomponents, $canconfirm, $editbugs) = @$group;
        my $newentry = $cgi->param("entry_$groupid") || 0;
        my $newmembercontrol = $cgi->param("membercontrol_$groupid") || 0;
        my $newothercontrol = $cgi->param("othercontrol_$groupid") || 0;
        my $newcanedit = $cgi->param("canedit_$groupid") || 0;
        my $new_editcomponents = $cgi->param("editcomponents_$groupid") || 0;
        my $new_canconfirm = $cgi->param("canconfirm_$groupid") || 0;
        my $new_editbugs = $cgi->param("editbugs_$groupid") || 0;

        my $oldentry = $entry;
        # Set undefined values to 0.
        $entry ||= 0;
        $membercontrol ||= 0;
        $othercontrol ||= 0;
        $canedit ||= 0;
        $editcomponents ||= 0;
        $canconfirm ||= 0;
        $editbugs ||= 0;

        # We use them in placeholders only. So it's safe to detaint them.
        detaint_natural($newentry);
        detaint_natural($newothercontrol);
        detaint_natural($newmembercontrol);
        detaint_natural($newcanedit);
        detaint_natural($new_editcomponents);
        detaint_natural($new_canconfirm);
        detaint_natural($new_editbugs);

        if (!defined($oldentry)
            && ($newentry || $newmembercontrol || $newcanedit
                || $new_editcomponents || $new_canconfirm || $new_editbugs))
        {
            $sth_Insert->execute($groupid, $product->id, $newentry,
                                 $newmembercontrol, $newothercontrol, $newcanedit,
                                 $new_editcomponents, $new_canconfirm, $new_editbugs);
        }
        elsif (($newentry != $entry)
               || ($newmembercontrol != $membercontrol)
               || ($newothercontrol != $othercontrol)
               || ($newcanedit != $canedit)
               || ($new_editcomponents != $editcomponents)
               || ($new_canconfirm != $canconfirm)
               || ($new_editbugs != $editbugs))
        {
            $sth_Update->execute($newentry, $newmembercontrol, $newothercontrol,
                                 $newcanedit, $new_editcomponents, $new_canconfirm,
                                 $new_editbugs, $groupid, $product->id);
        }

        if (!$newentry && !$newmembercontrol && !$newothercontrol
            && !$newcanedit && !$new_editcomponents && !$new_canconfirm
            && !$new_editbugs)
        {
            $sth_Delete->execute($groupid, $product->id);
        }
    }

    my $sth_Select = $dbh->prepare(
                     'SELECT bugs.bug_id,
                   CASE WHEN (lastdiffed >= delta_ts) THEN 1 ELSE 0 END
                        FROM bugs
                  INNER JOIN bug_group_map
                          ON bug_group_map.bug_id = bugs.bug_id
                       WHERE group_id = ?
                         AND bugs.product_id = ?
                    ORDER BY bugs.bug_id');

    my $sth_Select2 = $dbh->prepare('SELECT name, NOW() FROM groups WHERE id = ?');

    $sth_Update = $dbh->prepare('UPDATE bugs SET delta_ts = ? WHERE bug_id = ?');

    my $sth_Update2 = $dbh->prepare('UPDATE bugs SET delta_ts = ?, lastdiffed = ?
                                     WHERE bug_id = ?');

    $sth_Delete = $dbh->prepare('DELETE FROM bug_group_map
                                 WHERE bug_id = ? AND group_id = ?');

    my @removed_na;
    foreach my $groupid (@now_na) {
        my $count = 0;
        my $bugs = $dbh->selectall_arrayref($sth_Select, undef,
                                            ($groupid, $product->id));

        my ($removed, $timestamp) =
            $dbh->selectrow_array($sth_Select2, undef, $groupid);

        foreach my $bug (@$bugs) {
            my ($bugid, $mailiscurrent) = @$bug;
            $sth_Delete->execute($bugid, $groupid);

            LogActivityEntry($bugid, "bug_group", $removed, "",
                             $whoid, $timestamp);

            if ($mailiscurrent) {
                $sth_Update2->execute($timestamp, $timestamp, $bugid);
            }
            else {
                $sth_Update->execute($timestamp, $bugid);
            }
            $count++;
        }
        my %group = (name => $removed, bug_count => $count);

        push(@removed_na, \%group);
    }

    $sth_Select = $dbh->prepare(
                  'SELECT bugs.bug_id,
                CASE WHEN (lastdiffed >= delta_ts) THEN 1 ELSE 0 END
                     FROM bugs
                LEFT JOIN bug_group_map
                       ON bug_group_map.bug_id = bugs.bug_id
                      AND group_id = ?
                    WHERE bugs.product_id = ?
                      AND bug_group_map.bug_id IS NULL
                 ORDER BY bugs.bug_id');

    $sth_Insert = $dbh->prepare('INSERT INTO bug_group_map
                                 (bug_id, group_id) VALUES (?, ?)');

    my @added_mandatory;
    foreach my $groupid (@now_mandatory) {
        my $count = 0;
        my $bugs = $dbh->selectall_arrayref($sth_Select, undef,
                                            ($groupid, $product->id));

        my ($added, $timestamp) =
            $dbh->selectrow_array($sth_Select2, undef, $groupid);

        foreach my $bug (@$bugs) {
            my ($bugid, $mailiscurrent) = @$bug;
            $sth_Insert->execute($bugid, $groupid);

            LogActivityEntry($bugid, "bug_group", "", $added,
                             $whoid, $timestamp);

            if ($mailiscurrent) {
                $sth_Update2->execute($timestamp, $timestamp, $bugid);
            }
            else {
                $sth_Update->execute($timestamp, $bugid);
            }
            $count++;
        }
        my %group = (name => $added, bug_count => $count);

        push(@added_mandatory, \%group);
    }
    $dbh->bz_commit_transaction();

    delete_token($token);

    $vars->{'removed_na'} = \@removed_na;
    $vars->{'added_mandatory'} = \@added_mandatory;
    $vars->{'product'} = $product;

    $template->process("admin/products/groupcontrol/updated.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
    exit;
}

#
# action='update' -> update the product
#
if ($action eq 'update') {
    check_token_data($token, 'edit_product');
    my $product_old_name = trim($cgi->param('product_old_name') || '');
    my $product = $user->check_can_admin_product($product_old_name);

    $product->set_name($product_name);
    $product->set_description(scalar $cgi->param('description'));
    $product->set_default_milestone(scalar $cgi->param('defaultmilestone'));
    $product->set_milestone_url(scalar $cgi->param('milestoneurl'));
    $product->set_disallow_new(scalar $cgi->param('disallownew'));
    $product->set_votes_per_user(scalar $cgi->param('votesperuser'));
    $product->set_votes_per_bug(scalar $cgi->param('maxvotesperbug'));
    $product->set_votes_to_confirm(scalar $cgi->param('votestoconfirm'));

    my $changes = $product->update();

    delete_token($token);

    if (Bugzilla->params->{'useclassification'}) {
        $vars->{'classification'} = new Bugzilla::Classification($product->classification_id);
    }
    $vars->{'product'} = $product;
    $vars->{'changes'} = $changes;

    $template->process("admin/products/updated.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
    exit;
}

#
# action='editgroupcontrols' -> update product group controls
#

if ($action eq 'editgroupcontrols') {
    my $product = $user->check_can_admin_product($product_name);

    # Display a group if it is either enabled or has bugs for this product.
    my $groups = $dbh->selectall_arrayref(
        'SELECT id, name, entry, membercontrol, othercontrol, canedit,
                editcomponents, editbugs, canconfirm,
                isactive, COUNT(bugs.bug_id) AS bugcount
           FROM groups
      LEFT JOIN group_control_map
             ON group_control_map.group_id = groups.id
            AND group_control_map.product_id = ?
      LEFT JOIN bug_group_map
             ON bug_group_map.group_id = groups.id
      LEFT JOIN bugs
             ON bugs.bug_id = bug_group_map.bug_id
            AND bugs.product_id = ?
          WHERE isbuggroup != 0
            AND (isactive != 0 OR entry IS NOT NULL OR bugs.bug_id IS NOT NULL) ' .
           $dbh->sql_group_by('name', 'id, entry, membercontrol,
                              othercontrol, canedit, isactive,
                              editcomponents, canconfirm, editbugs'),
        {'Slice' => {}}, ($product->id, $product->id));

    $vars->{'product'} = $product;
    $vars->{'groups'} = $groups;
    $vars->{'token'} = issue_session_token('edit_group_controls');

    $vars->{'const'} = {
        'CONTROLMAPNA' => CONTROLMAPNA,
        'CONTROLMAPSHOWN' => CONTROLMAPSHOWN,
        'CONTROLMAPDEFAULT' => CONTROLMAPDEFAULT,
        'CONTROLMAPMANDATORY' => CONTROLMAPMANDATORY,
    };

    $template->process("admin/products/groupcontrol/edit.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
    exit;                
}


#
# No valid action found
#

ThrowUserError('no_valid_action', {field => "product"});
