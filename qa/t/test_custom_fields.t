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
log_in($sel, $config, 'admin');

# Create new bug to test custom fields

file_bug_in_product($sel, 'TestProduct');
my $bug_summary = "What's your ID?";
$sel->type_ok("short_desc", $bug_summary);
$sel->type_ok("comment", "Use the ID of this bug to generate a unique custom field name.");
$sel->type_ok("bug_severity", "label=normal");
my $bug1_id = create_bug($sel, $bug_summary);

# Create custom fields

go_to_admin($sel);
$sel->click_ok("link=Custom Fields");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Fields");
$sel->click_ok("link=Add a new custom field");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add a new Custom Field");
$sel->type_ok("name", "cf_qa_freetext_$bug1_id");
$sel->type_ok("desc", "Freetext$bug1_id");
$sel->select_ok("type", "label=Free Text");
$sel->type_ok("sortkey", $bug1_id);
# These values are off by default.
$sel->value_is("enter_bug", "off");
$sel->value_is("obsolete", "off");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Field Created");
$sel->is_text_present_ok("The new custom field 'cf_qa_freetext_$bug1_id' has been successfully created.");

$sel->click_ok("link=Add a new custom field");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add a new Custom Field");
$sel->type_ok("name", "cf_qa_list_$bug1_id");
$sel->type_ok("desc", "List$bug1_id");
$sel->select_ok("type", "label=Drop Down");
$sel->type_ok("sortkey", $bug1_id);
$sel->click_ok("enter_bug");
$sel->value_is("enter_bug", "on");
$sel->click_ok("new_bugmail");
$sel->value_is("new_bugmail", "on");
$sel->value_is("obsolete", "off");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Field Created");
$sel->is_text_present_ok("The new custom field 'cf_qa_list_$bug1_id' has been successfully created.");

$sel->click_ok("link=Add a new custom field");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add a new Custom Field");
$sel->type_ok("name", "cf_qa_bugid_$bug1_id");
$sel->type_ok("desc", "Reference$bug1_id");
$sel->select_ok("type", "label=Bug ID");
$sel->type_ok("sortkey", $bug1_id);
$sel->type_ok("reverse_desc", "IsRef$bug1_id");
$sel->click_ok("enter_bug");
$sel->value_is("enter_bug", "on");
$sel->value_is("obsolete", "off");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Field Created");
$sel->is_text_present_ok("The new custom field 'cf_qa_bugid_$bug1_id' has been successfully created.");

# Add values to the custom fields.

$sel->click_ok("link=cf_qa_list_$bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit the Custom Field 'cf_qa_list_$bug1_id' (List$bug1_id)");
$sel->click_ok("link=Edit legal values for this field");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select value for the 'List$bug1_id' (cf_qa_list_$bug1_id) field");

$sel->click_ok("link=Add");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add Value for the 'List$bug1_id' (cf_qa_list_$bug1_id) field");
$sel->type_ok("value", "have fun?");
$sel->type_ok("sortkey", "805");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("New Field Value Created");
$sel->is_text_present_ok("The value have fun? has been added as a valid choice for the List$bug1_id (cf_qa_list_$bug1_id) field.");

$sel->click_ok("link=Add");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add Value for the 'List$bug1_id' (cf_qa_list_$bug1_id) field");
$sel->type_ok("value", "storage");
$sel->type_ok("sortkey", "49");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("New Field Value Created");
$sel->is_text_present_ok("The value storage has been added as a valid choice for the List$bug1_id (cf_qa_list_$bug1_id) field.");

# Also create a new bug status and a new resolution.

go_to_admin($sel);
$sel->click_ok("link=Field Values");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit values for which field?");
$sel->click_ok("link=Resolution");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select value for the 'Resolution' (resolution) field");
$sel->click_ok("link=Add");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add Value for the 'Resolution' (resolution) field");
$sel->type_ok("value", "UPSTREAM");
$sel->type_ok("sortkey", 450);
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("New Field Value Created");

go_to_admin($sel);
$sel->click_ok("link=Field Values");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit values for which field?");
$sel->click_ok("link=Status");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select value for the 'Status' (bug_status) field");
$sel->click_ok("link=Add");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add Value for the 'Status' (bug_status) field");
$sel->type_ok("value", "SUSPENDED");
$sel->type_ok("sortkey", 250);
$sel->click_ok("open_status");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("New Field Value Created");

$sel->click_ok("link=Add");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add Value for the 'Status' (bug_status) field");
$sel->type_ok("value", "IN_QA");
$sel->type_ok("sortkey", 550);
$sel->click_ok("closed_status");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("New Field Value Created");

$sel->click_ok("link=status workflow page");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Workflow");
$sel->click_ok('//td[@title="From UNCONFIRMED to SUSPENDED"]//input[@type="checkbox"]');
$sel->click_ok('//td[@title="From CONFIRMED to SUSPENDED"]//input[@type="checkbox"]');
$sel->click_ok('//td[@title="From SUSPENDED to CONFIRMED"]//input[@type="checkbox"]');
$sel->click_ok('//td[@title="From SUSPENDED to IN_PROGRESS"]//input[@type="checkbox"]');
$sel->click_ok('//td[@title="From RESOLVED to IN_QA"]//input[@type="checkbox"]');
$sel->click_ok('//td[@title="From IN_QA to VERIFIED"]//input[@type="checkbox"]');
$sel->click_ok('//td[@title="From IN_QA to CONFIRMED"]//input[@type="checkbox"]');
$sel->click_ok('//input[@value="Commit Changes"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Workflow");

# Create new bug to test custom fields in bug creation page

file_bug_in_product($sel, 'TestProduct');
$sel->is_text_present_ok("List$bug1_id:");
$sel->is_element_present_ok("cf_qa_list_$bug1_id");
$sel->is_text_present_ok("Reference$bug1_id:");
$sel->is_element_present_ok("cf_qa_bugid_$bug1_id");
ok(!$sel->is_text_present("Freetext$bug1_id:"), "Freetext$bug1_id is not displayed");
ok(!$sel->is_element_present("cf_qa_freetext_$bug1_id"), "cf_qa_freetext_$bug1_id is not available");
my $bug_summary2 = "Et de un";
$sel->type_ok("short_desc", $bug_summary2);
$sel->select_ok("bug_severity", "critical");
$sel->type_ok("cf_qa_bugid_$bug1_id", $bug1_id);
$sel->type_ok("comment", "hops!");
my $bug2_id = create_bug($sel, $bug_summary2);

# Both fields are editable.

$sel->type_ok("cf_qa_freetext_$bug1_id", "bonsai");
$sel->selected_label_is("cf_qa_list_$bug1_id", "---");
$sel->select_ok("bug_status", "label=SUSPENDED");
edit_bug($sel, $bug2_id);

go_to_bug($sel, $bug1_id);
$sel->type_ok("cf_qa_freetext_$bug1_id", "dumbo");
$sel->select_ok("cf_qa_list_$bug1_id", "label=storage");
$sel->is_text_present_ok("IsRef$bug1_id: $bug2_id");
$sel->select_ok("bug_status", "RESOLVED");
$sel->select_ok("resolution", "UPSTREAM");
edit_bug_and_return($sel, $bug1_id, $bug_summary);
$sel->select_ok("bug_status", "IN_QA");
edit_bug_and_return($sel, $bug1_id, $bug_summary);

$sel->click_ok("link=Format For Printing");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Full Text Bug Listing");
$sel->is_text_present_ok("Freetext$bug1_id: dumbo");
$sel->is_text_present_ok("List$bug1_id: storage");
$sel->is_text_present_ok("Status: IN_QA UPSTREAM");
go_to_bug($sel, $bug2_id);
$sel->select_ok("cf_qa_list_$bug1_id", "label=storage");
edit_bug($sel, $bug2_id);

# Test searching for bugs using the custom fields

open_advanced_search_page($sel);
$sel->remove_all_selections_ok("product");
$sel->add_selection_ok("product", "TestProduct");
$sel->remove_all_selections("bug_status");
$sel->remove_all_selections("resolution");
$sel->select_ok("f1", "label=List$bug1_id");
$sel->select_ok("o1", "label=is equal to");
$sel->type_ok("v1", "storage");
$sel->click_ok("Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("2 bugs found");
$sel->is_text_present_ok("What's your ID?");
$sel->is_text_present_ok("Et de un");

# Now edit custom fields in mass changes.

$sel->click_ok("link=Change Several Bugs at Once");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->click_ok("check_all");
$sel->select_ok("cf_qa_list_$bug1_id", "label=---");
$sel->type_ok("cf_qa_freetext_$bug1_id", "thanks");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bugs processed");
$sel->click_ok("link=bug $bug2_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug2_id/);
$sel->value_is("cf_qa_freetext_$bug1_id", "thanks");
$sel->selected_label_is("cf_qa_list_$bug1_id", "---");
$sel->select_ok("cf_qa_list_$bug1_id", "label=storage");
edit_bug($sel, $bug2_id);

# Let's now test custom field visibility.

go_to_admin($sel);
$sel->click_ok("link=Custom Fields");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Fields");
$sel->click_ok("link=cf_qa_list_$bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit the Custom Field 'cf_qa_list_$bug1_id' (List$bug1_id)");
$sel->select_ok("visibility_field_id", "label=Severity (bug_severity)");
$sel->select_ok("visibility_values", "label=critical");
$sel->click_ok("edit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Field Updated");

go_to_bug($sel, $bug1_id);
$sel->is_element_present_ok("cf_qa_list_$bug1_id", "List$bug1_id is in the DOM of the page...");
ok(!$sel->is_visible("cf_qa_list_$bug1_id"), "... but is not displayed with severity = 'normal'");
$sel->select_ok("bug_severity", "major");
ok(!$sel->is_visible("cf_qa_list_$bug1_id"), "... nor with severity = 'major'");
$sel->select_ok("bug_severity", "critical");
$sel->is_visible_ok("cf_qa_list_$bug1_id", "... but is visible with severity = 'critical'");
edit_bug_and_return($sel, $bug1_id, $bug_summary);
$sel->is_visible_ok("cf_qa_list_$bug1_id");

go_to_bug($sel, $bug2_id);
$sel->is_visible_ok("cf_qa_list_$bug1_id");
$sel->select_ok("bug_severity", "minor");
ok(!$sel->is_visible("cf_qa_list_$bug1_id"), "List$bug1_id is not displayed with severity = 'minor'");
edit_bug_and_return($sel, $bug2_id, $bug_summary2);
ok(!$sel->is_visible("cf_qa_list_$bug1_id"), "List$bug1_id is not displayed with severity = 'minor'");

# Add a new value which is only listed under some condition.

go_to_admin($sel);
$sel->click_ok("link=Custom Fields");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Fields");
$sel->click_ok("link=cf_qa_list_$bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit the Custom Field 'cf_qa_list_$bug1_id' (List$bug1_id)");
$sel->select_ok("value_field_id", "label=Resolution (resolution)");
$sel->click_ok("edit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Field Updated");
$sel->click_ok("link=cf_qa_list_$bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit the Custom Field 'cf_qa_list_$bug1_id' (List$bug1_id)");
$sel->click_ok("link=Edit legal values for this field");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select value for the 'List$bug1_id' (cf_qa_list_$bug1_id) field");
$sel->click_ok("link=Add");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add Value for the 'List$bug1_id' (cf_qa_list_$bug1_id) field");
$sel->type_ok("value", "ghost");
$sel->type_ok("sortkey", "500");
$sel->select_ok("visibility_value_id", "label=FIXED");
$sel->click_ok("id=create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("New Field Value Created");

go_to_bug($sel, $bug1_id);
my @labels = $sel->get_select_options("cf_qa_list_$bug1_id");
ok(grep(/^ghost$/, @labels), "ghost is in the DOM of the page...");
my $disabled = $sel->get_attribute("v4_cf_qa_list_$bug1_id\@disabled");
ok($disabled, "... but is not available for selection by default");
$sel->select_ok("bug_status", "label=RESOLVED");
$sel->select_ok("resolution", "label=FIXED");
$sel->select_ok("cf_qa_list_$bug1_id", "label=ghost");
edit_bug_and_return($sel, $bug1_id, $bug_summary);
$sel->selected_label_is("cf_qa_list_$bug1_id", "ghost");

# Delete an unused field value.

go_to_admin($sel);
$sel->click_ok("link=Field Values");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit values for which field?");
$sel->click_ok("link=List$bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select value for the 'List$bug1_id' (cf_qa_list_$bug1_id) field");
$sel->click_ok("//a[contains(\@href, 'editvalues.cgi?action=del&field=cf_qa_list_$bug1_id&value=have%20fun%3F')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Value 'have fun?' from the 'List$bug1_id' (cf_qa_list_$bug1_id) field");
$sel->is_text_present_ok("Do you really want to delete this value?");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Field Value Deleted");

# This value cannot be deleted as it's in use.

$sel->click_ok("//a[contains(\@href, 'editvalues.cgi?action=del&field=cf_qa_list_$bug1_id&value=storage')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Value 'storage' from the 'List$bug1_id' (cf_qa_list_$bug1_id) field");
$sel->is_text_present_ok("There is 1 bug with this field value");

# Mark the <select> field as obsolete, making it unavailable in bug reports.

go_to_admin($sel);
$sel->click_ok("link=Custom Fields");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Fields");
$sel->click_ok("link=cf_qa_list_$bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit the Custom Field 'cf_qa_list_$bug1_id' (List$bug1_id)");
$sel->click_ok("obsolete");
$sel->value_is("obsolete", "on");
$sel->click_ok("edit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Field Updated");
go_to_bug($sel, $bug1_id);
$sel->value_is("cf_qa_freetext_$bug1_id", "thanks");
ok(!$sel->is_element_present("cf_qa_list_$bug1_id"), "The custom list is not visible");

# Custom fields are also viewable by logged out users.

logout($sel);
go_to_bug($sel, $bug1_id);
$sel->is_text_present_ok("Freetext$bug1_id: thanks");

# Powerless users should still be able to CC themselves when
# custom fields are in use.

log_in($sel, $config, 'unprivileged');
go_to_bug($sel, $bug1_id);
$sel->is_text_present_ok("Freetext$bug1_id: thanks");
$sel->click_ok("cc_edit_area_showhide");
$sel->type_ok("newcc", $config->{unprivileged_user_login});
edit_bug($sel, $bug1_id);
logout($sel);

# Disable the remaining free text field.

log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok("link=Custom Fields");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Fields");
$sel->click_ok("link=cf_qa_freetext_$bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit the Custom Field 'cf_qa_freetext_$bug1_id' (Freetext$bug1_id)");
$sel->click_ok("obsolete");
$sel->value_is("obsolete", "on");
$sel->click_ok("edit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Field Updated");

# Trying to delete a bug status which is in use is forbidden.

go_to_admin($sel);
$sel->click_ok("link=Field Values");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit values for which field?");
$sel->click_ok("link=Status");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select value for the 'Status' (bug_status) field");
$sel->click_ok('//a[@href="editvalues.cgi?action=del&field=bug_status&value=SUSPENDED"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Value 'SUSPENDED' from the 'Status' (bug_status) field");
$sel->is_text_present_ok("Sorry, but the 'SUSPENDED' value cannot be deleted");

go_to_bug($sel, $bug2_id);
$sel->select_ok("bug_status", "CONFIRMED");
edit_bug($sel, $bug2_id);

go_to_bug($sel, $bug1_id);
$sel->select_ok("bug_status", "VERIFIED");
$sel->select_ok("resolution", "INVALID");
edit_bug($sel, $bug1_id);

# Unused values can be deleted.

go_to_admin($sel);
$sel->click_ok("link=Field Values");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit values for which field?");
$sel->click_ok("link=Status");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select value for the 'Status' (bug_status) field");
$sel->click_ok('//a[@href="editvalues.cgi?action=del&field=bug_status&value=SUSPENDED"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Value 'SUSPENDED' from the 'Status' (bug_status) field");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Field Value Deleted");
$sel->is_text_present_ok("The value SUSPENDED of the Status (bug_status) field has been deleted");

$sel->click_ok('//a[@href="editvalues.cgi?action=del&field=bug_status&value=IN_QA"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Value 'IN_QA' from the 'Status' (bug_status) field");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Field Value Deleted");
$sel->is_text_present_ok("The value IN_QA of the Status (bug_status) field has been deleted");

go_to_admin($sel);
$sel->click_ok("link=Field Values");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit values for which field?");
$sel->click_ok("link=Resolution");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select value for the 'Resolution' (resolution) field");
$sel->click_ok('//a[@href="editvalues.cgi?action=del&field=resolution&value=UPSTREAM"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Value 'UPSTREAM' from the 'Resolution' (resolution) field");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Field Value Deleted");
$sel->is_text_present_ok("The value UPSTREAM of the Resolution (resolution) field has been deleted");

logout($sel);
