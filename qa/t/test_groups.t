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

# Add the new Selenium-test group.

log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("link=Add Group");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Add group");
$sel->type_ok("name", "Selenium-test");
$sel->type_ok("desc", "Test group for Selenium");
$sel->type_ok("owner", $config->{'admin_user_login'});
$sel->check_ok("isactive");
$sel->uncheck_ok("insertnew");
$sel->click_ok("create");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("New Group Created");
my $group_id = $sel->get_value("group_id");

# Mark the Selenium-test group as Shown/Mandatory for TestProduct.

edit_product($sel, "TestProduct");
$sel->click_ok("link=Edit Group Access Controls:");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Edit Group Controls for TestProduct");
$sel->is_text_present_ok("Selenium-test");
$sel->select_ok("membercontrol_${group_id}", "label=Shown");
$sel->select_ok("othercontrol_${group_id}", "label=Mandatory");
$sel->click_ok("submit");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Update group access controls for TestProduct");

# File a new bug in the TestProduct product, and restrict it to the bug group.

file_bug_in_product($sel, "TestProduct");
$sel->is_text_present_ok("Test group for Selenium");
$sel->value_is("group_${group_id}", "off"); # Must be OFF (else that's a bug)
$sel->check_ok("group_${group_id}");
$sel->type_ok("short_desc", "bug restricted to the Selenium group");
$sel->type_ok("comment", "should be invisible");
$sel->selected_label_is("component", "TestComponent");
$sel->click_ok("commit");
$sel->wait_for_page_to_load(WAIT_TIME);
my $bug1_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
$sel->is_text_present_ok('has been added to the database', "Bug $bug1_id created");
$sel->is_text_present_ok("Test group for Selenium");
$sel->value_is("group_${group_id}", "on"); # Must be ON

# Look for this new bug and add it to the new "Selenium bugs" saved search.

open_advanced_search_page($sel);
$sel->remove_all_selections_ok("product");
$sel->add_selection_ok("product", "TestProduct");
$sel->remove_all_selections("bug_status");
$sel->add_selection_ok("bug_status", "UNCONFIRMED");
$sel->add_selection_ok("bug_status", "CONFIRMED");
$sel->select_ok("f1", "Group");
$sel->select_ok("o1", "is equal to");
$sel->type_ok("v1", "Selenium-test");
$sel->click_ok("Search");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("One bug found");
$sel->is_text_present_ok("bug restricted to the Selenium group");
$sel->type_ok("save_newqueryname", "Selenium bugs");
$sel->click_ok("remember");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->is_text_present_ok("OK, you have a new search named Selenium bugs");
$sel->click_ok("link=Selenium bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: Selenium bugs");
$sel->is_text_present_ok("One bug found");
$sel->is_element_present_ok("b$bug1_id", undef, "Bug $bug1_id restricted to the bug group");

# No longer use Selenium-test as a bug group.

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("link=Selenium-test");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Change Group: Selenium-test");
$sel->value_is("isactive", "on");
$sel->click_ok("isactive");
$sel->click_ok('//input[@value="Update Group"]');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Change Group: Selenium-test");
$sel->is_text_present_ok("The group will no longer be used for bugs");

# File another new bug, now visible as the bug group is disabled.

file_bug_in_product($sel, "TestProduct");
$sel->selected_label_is("component", "TestComponent");
$sel->type_ok("short_desc", "bug restricted to the Selenium group");
$sel->type_ok("comment", "should be *visible* when created (the group is disabled)");
ok(!$sel->is_text_present("Test group for Selenium"), "Selenium-test group unavailable");
ok(!$sel->is_element_present("group_${group_id}"), "Selenium-test checkbox not present");
$sel->click_ok("commit");
$sel->wait_for_page_to_load(WAIT_TIME);
my $bug2_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");
$sel->is_text_present_ok('has been added to the database', "Bug $bug2_id created");

# Make sure the new bug doesn't appear in the "Selenium bugs" saved search.

$sel->click_ok("link=Selenium bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: Selenium bugs");
$sel->is_text_present_ok("One bug found");
$sel->is_element_present_ok("b$bug1_id", undef, "Bug $bug1_id restricted to the bug group");
ok(!$sel->is_element_present("b$bug2_id"), "Bug $bug2_id NOT restricted to the bug group");

# Re-enable the Selenium-test group as bug group. This doesn't affect
# already filed bugs as this group is not mandatory.

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("link=Selenium-test");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->value_is("isactive", "off");
$sel->click_ok("isactive");
$sel->title_is("Change Group: Selenium-test");
$sel->click_ok('//input[@value="Update Group"]');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Change Group: Selenium-test");
$sel->is_text_present_ok("The group will now be used for bugs");

# Make sure the second filed bug has not been added to the bug group.

$sel->click_ok("link=Selenium bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: Selenium bugs");
$sel->is_text_present_ok("One bug found");
$sel->is_element_present_ok("b$bug1_id", undef, "Bug $bug1_id restricted to the bug group");
ok(!$sel->is_element_present("b$bug2_id"), "Bug $bug2_id NOT restricted to the bug group");

# Make the Selenium-test group mandatory for TestProduct.

edit_product($sel, "TestProduct");
$sel->is_text_present_ok("Selenium-test: Shown/Mandatory");
$sel->click_ok("link=Edit Group Access Controls:");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->select_ok("membercontrol_${group_id}", "Mandatory");
$sel->click_ok("submit");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Confirm Group Control Change for product 'TestProduct'");
$sel->is_text_present_ok("the group is newly mandatory and will be added");
$sel->click_ok("update");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Update group access controls for TestProduct");
$sel->is_text_present_ok('regexp:Adding bugs to group \'Selenium-test\' which is\W+mandatory for this product');

# All bugs being in TestProduct must now be restricted to the bug group.

$sel->click_ok("link=Selenium bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: Selenium bugs");
$sel->is_element_present_ok("b$bug1_id", undef, "Bug $bug1_id restricted to the bug group");
$sel->is_element_present_ok("b$bug2_id", undef, "Bug $bug2_id restricted to the bug group");

# File a new bug, which must automatically be restricted to the bug group.

file_bug_in_product($sel, "TestProduct");
$sel->selected_label_is("component", "TestComponent");
$sel->type_ok("short_desc", "Selenium-test group mandatory");
$sel->type_ok("comment", "group enabled");
ok(!$sel->is_text_present("Test group for Selenium"), "Selenium-test group not available");
ok(!$sel->is_element_present("group_${group_id}"), "Selenium-test checkbox not present (mandatory group)");
$sel->click_ok("commit");
$sel->wait_for_page_to_load(WAIT_TIME);
my $bug3_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");
$sel->is_text_present_ok('has been added to the database', "Bug $bug3_id created");

# Make sure all three bugs are listed as being restricted to the bug group.

$sel->click_ok("link=Selenium bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: Selenium bugs");
$sel->is_element_present_ok("b$bug1_id", undef, "Bug $bug1_id restricted to the bug group");
$sel->is_element_present_ok("b$bug2_id", undef, "Bug $bug2_id restricted to the bug group");
$sel->is_element_present_ok("b$bug3_id", undef, "Bug $bug3_id restricted to the bug group");

# Turn off the Selenium-test group again.

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("link=Selenium-test");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Change Group: Selenium-test");
$sel->value_is("isactive", "on");
$sel->click_ok("isactive");
$sel->click_ok("//input[\@value='Update Group']");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Change Group: Selenium-test");
$sel->is_text_present_ok("The group will no longer be used for bugs");

# File a bug again. It should not be added to the bug group as this one is disabled.

file_bug_in_product($sel, "TestProduct");
$sel->selected_label_is("component", "TestComponent");
$sel->type_ok("short_desc", "bug restricted to the Selenium-test group");
$sel->type_ok("comment", "group disabled");
ok(!$sel->is_text_present("Test group for Selenium"), "Selenium-test group not available");
ok(!$sel->is_element_present("group_${group_id}"), "Selenium-test checkbox not present");
$sel->click_ok("commit");
$sel->wait_for_page_to_load(WAIT_TIME);
my $bug4_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");
$sel->is_text_present_ok('has been added to the database', "Bug $bug4_id created");

# The last bug must not be in the list.

$sel->click_ok("link=Selenium bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: Selenium bugs");
$sel->is_element_present_ok("b$bug1_id", undef, "Bug $bug1_id restricted to the bug group");
$sel->is_element_present_ok("b$bug2_id", undef, "Bug $bug2_id restricted to the bug group");
$sel->is_element_present_ok("b$bug3_id", undef, "Bug $bug3_id restricted to the bug group");
ok(!$sel->is_element_present("b$bug4_id"), "Bug $bug4_id NOT restricted to the bug group");

# Re-enable the mandatory group. All bugs should be restricted to this bug group automatically.

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("link=Selenium-test");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Change Group: Selenium-test");
$sel->value_is("isactive", "off");
$sel->click_ok("isactive");
$sel->click_ok("//input[\@value='Update Group']");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Change Group: Selenium-test");
$sel->is_text_present_ok("The group will now be used for bugs");

# Make sure all bugs are restricted to the bug group.

$sel->click_ok("link=Selenium bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: Selenium bugs");
$sel->is_element_present_ok("b$bug1_id", undef, "Bug $bug1_id restricted to the bug group");
$sel->is_element_present_ok("b$bug2_id", undef, "Bug $bug2_id restricted to the bug group");
$sel->is_element_present_ok("b$bug3_id", undef, "Bug $bug3_id restricted to the bug group");
$sel->is_element_present_ok("b$bug4_id", undef, "Bug $bug4_id restricted to the bug group");

# Try to remove the Selenium-test group from TestProduct, but DON'T do it!
# We just want to make sure a warning is displayed about this removal.

edit_product($sel, "TestProduct");
$sel->is_text_present_ok("Selenium-test: Mandatory/Mandatory");
$sel->click_ok("link=Edit Group Access Controls:");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Edit Group Controls for TestProduct");
$sel->is_text_present_ok("Selenium-test");
$sel->select_ok("membercontrol_${group_id}", "NA");
$sel->select_ok("othercontrol_${group_id}", "NA");
$sel->click_ok("submit");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Confirm Group Control Change for product 'TestProduct'");
$sel->is_text_present_ok("the group is no longer applicable and will be removed");

# Delete the Selenium-test group.

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("//a[\@href='editgroups.cgi?action=del&group=${group_id}']");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Delete group");
$sel->is_text_present_ok("Do you really want to delete this group?");
$sel->is_element_present_ok("removebugs");
$sel->value_is("removebugs", "off");
$sel->is_text_present_ok("Remove all bugs from this group restriction for me");
$sel->is_element_present_ok("unbind");
$sel->value_is("unbind", "off");
$sel->is_text_present_ok("remove these controls");
$sel->click_ok("delete");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Cannot Delete Group");
my $error_msg = trim($sel->get_text("error_msg"));
ok($error_msg =~ /^The Selenium-test group cannot be deleted/, "Group is in use - not deletable");
$sel->go_back_ok();
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->check("removebugs");
$sel->check("unbind");
$sel->click_ok("delete");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Group Deleted");
$sel->is_text_present_ok("The group Selenium-test has been deleted.");

# No more bugs listed in the saved search as the bug group is gone.

$sel->click_ok("link=Selenium bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: Selenium bugs");
$sel->is_text_present_ok("Zarro Boogs found");
$sel->click_ok("link=Forget Search 'Selenium bugs'");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Search is gone");
$sel->is_text_present_ok("OK, the Selenium bugs search is gone.");
logout($sel);
