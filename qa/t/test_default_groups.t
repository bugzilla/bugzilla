# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More "no_plan";

use QA::Util;

my ($sel, $config) = get_selenium();

# Turn on the makeproductgroups parameter. Create a new product and check that
# it has automatically a group created for it with the same name.

log_in($sel, $config, 'admin');
set_parameters($sel, { "Group Security" => {"makeproductgroups-on" => undef} });
add_product($sel);
$sel->type_ok("product", "ready_to_die");
$sel->type_ok("description", "will die");
$sel->select_ok("security_group_id", "label=core-security");
$sel->select_ok("default_op_sys_id", "Unspecified");
$sel->select_ok("default_platform_id", "Unspecified");
$sel->click_ok('//input[@value="Add"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Created");
go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("link=ready_to_die");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Group: ready_to_die");
my $group_url = $sel->get_location();
$group_url =~ /group=(\d+)/;
my $group1_id = $1;
$sel->value_is("desc", "Access to bugs in the ready_to_die product");
my @groups = $sel->get_select_options("members_remove");
ok((grep { $_ eq 'admin' } @groups), "'admin' inherits group membership");
@groups = $sel->get_select_options("bless_from_remove");
ok((grep { $_ eq 'admin' } @groups), "'admin' inherits can bless group membership");
$sel->is_checked_ok("isactive");

# Check that the automatically created product group has the membercontrol
# for it set to Default and othercontrol set to NA.

edit_product($sel, "ready_to_die");
$sel->click_ok("link=Edit Group Access Controls:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Group Controls for ready_to_die");
$sel->value_is("entry_$group1_id", "off");
$sel->value_is("canedit_$group1_id", "off");
$sel->selected_label_is("membercontrol_$group1_id", "Default");
$sel->selected_label_is("othercontrol_$group1_id", "NA");

edit_product($sel, "ready_to_die");
$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->click_ok('//a[@href="editproducts.cgi?action=del&product=ready_to_die"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Product 'ready_to_die'");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Deleted");

# The product has been deleted, but the group must survive.

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->is_text_present_ok("Access to bugs in the ready_to_die product");

# Create a new product. As the "ready_to_die" group already exists,
# a new "ready_to_die_" one must be created.

add_product($sel);
$sel->type_ok("product", "ready_to_die");
$sel->type_ok("description", "will die");
$sel->select_ok("security_group_id", "label=core-security");
$sel->select_ok("default_op_sys_id", "Unspecified");
$sel->select_ok("default_platform_id", "Unspecified");
$sel->click_ok('//input[@value="Add"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Created");

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("link=ready_to_die_");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Group: ready_to_die_");
$group_url = $sel->get_location();
$group_url =~ /group=(\d+)/;
my $group2_id = $1;
$sel->value_is("desc", "Access to bugs in the ready_to_die product");
@groups = $sel->get_select_options("members_remove");
ok((grep { $_ eq 'admin' } @groups), "'admin' inherits group membership");
@groups = $sel->get_select_options("bless_from_remove");
ok((grep { $_ eq 'admin' } @groups), "'admin' inherits can bless group membership");
$sel->value_is("isactive", "on");

# Check group settings. The old 'ready_to_die' group has no relationship
# with this new product, despite its identical name.

edit_product($sel, "ready_to_die");
$sel->click_ok("link=Edit Group Access Controls:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Group Controls for ready_to_die");
$sel->value_is("entry_$group1_id", "off");
$sel->value_is("entry_$group2_id", "off");
$sel->value_is("canedit_$group1_id", "off");
$sel->value_is("canedit_$group2_id", "off");
$sel->selected_label_is("membercontrol_$group1_id", "NA");
$sel->selected_label_is("othercontrol_$group1_id", "NA");
$sel->selected_label_is("membercontrol_$group2_id", "Default");
$sel->selected_label_is("othercontrol_$group2_id", "NA");

# Delete the ready_to_die_ group. It's bound to the ready_to_die product,
# so the deletion requires explicit agreement from the admin.

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("//a[contains(\@href, 'editgroups.cgi?action=del&group=$group2_id')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete group");
$sel->is_text_present_ok("This group is tied to the following products");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Cannot Delete Group");
my $text = trim($sel->get_text("error_msg"));
ok($text =~ qr/All references to this group must be removed/,
   "Group ready_to_die_ cannot be deleted as it is bound to a product");
$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete group");
$sel->click_ok("unbind");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Group Deleted");
$text = trim($sel->get_text("message"));
ok($text =~ qr/The group ready_to_die_ has been deleted/, "Group ready_to_die_ has been deleted");

edit_product($sel, "ready_to_die");
$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->click_ok('//a[@href="editproducts.cgi?action=del&product=ready_to_die"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Product 'ready_to_die'");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Deleted");

# Reset the makeproductgroups parameter. Now creating a new product must
# not create a new group, nor bind any group with it.

set_parameters($sel, { "Group Security" => {"makeproductgroups-off" => undef} });
add_product($sel);
$sel->type_ok("product", "ready_to_die");
$sel->type_ok("description", "will die");
$sel->select_ok("security_group_id", "label=core-security");
$sel->select_ok("default_op_sys_id", "Unspecified");
$sel->select_ok("default_platform_id", "Unspecified");
$sel->click_ok('//input[@value="Add"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Created");

# Make sure that all group controls are set to NA for this product.

edit_product($sel, "ready_to_die");
$sel->title_is("Edit Product 'ready_to_die'");
$sel->click_ok("link=Edit Group Access Controls:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Group Controls for ready_to_die");
$sel->value_is("entry_$group1_id", "off");
$sel->value_is("canedit_$group1_id", "off");
$sel->selected_label_is("membercontrol_$group1_id", "NA");
$sel->selected_label_is("othercontrol_$group1_id", "NA");

# Delete remaining groups and products.

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Groups");
ok(!$sel->is_text_present('ready_to_die__'), 'No ready_to_die__ group created');
$sel->click_ok("//a[contains(\@href, 'editgroups.cgi?action=del&group=$group1_id')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete group");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Group Deleted");
$text = trim($sel->get_text("message"));
ok($text =~ /The group ready_to_die has been deleted/, "Group ready_to_die has been deleted");

edit_product($sel, "ready_to_die");
$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->click_ok('//a[@href="editproducts.cgi?action=del&product=ready_to_die"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Product 'ready_to_die'");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Deleted");
logout($sel);
