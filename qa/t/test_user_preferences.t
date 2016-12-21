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

# Update default user preferences.

log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok("link=Default Preferences");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Default Preferences");
$sel->uncheck_ok("skin-enabled");
$sel->value_is("skin-enabled", "off");
$sel->check_ok("state_addselfcc-enabled");
$sel->select_ok("state_addselfcc", "label=Never");
$sel->check_ok("post_bug_submit_action-enabled");
$sel->select_ok("post_bug_submit_action", "label=Show the updated bug");
$sel->check_ok("per_bug_queries-enabled");
$sel->select_ok("per_bug_queries", "label=On");
$sel->uncheck_ok("zoom_textareas-enabled");
$sel->select_ok("zoom_textareas", "label=Off");
$sel->click_ok("update");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Default Preferences");

# Update own user preferences. Some of them should no longer be present.

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=General Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
ok(!$sel->is_element_present("skin"), "The 'skin' user preference is not present");
$sel->select_ok("state_addselfcc", "label=Site Default (Never)");
$sel->select_ok("post_bug_submit_action", "label=Site Default (Show the updated bug)");
$sel->select_ok("per_bug_queries", "label=Site Default (On)");
ok(!$sel->is_element_present("zoom_textareas"), "The 'zoom_textareas' user preference is not present");
$sel->click_ok("update");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("User Preferences");

# File a bug in the 'TestProduct' product. The form fields must follow user prefs.

file_bug_in_product($sel, 'TestProduct');
$sel->value_is("cc", "");
$sel->type_ok("short_desc", "First bug created");
$sel->type_ok("comment", "I'm not in the CC list.");
$sel->click_ok("commit");
$sel->wait_for_page_to_load(WAIT_TIME);
my $bug1_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
$sel->is_text_present_ok('has been added to the database', "Bug $bug1_id created");
$sel->value_is("addselfcc", "off");
$sel->select_ok("bug_status", "label=IN_PROGRESS");
$sel->click_ok("commit");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("editme_action");
$sel->value_is("short_desc", "First bug created");
$sel->value_is("addselfcc", "off");

# Tag the bug.

$sel->select_ok("lob_action", "label=Add");
$sel->type_ok("lob_newqueryname", "sel-tmp");
$sel->type_ok("bug_ids", $bug1_id);
$sel->click_ok("commit_list_of_bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Tag Updated");
my $text = trim($sel->get_text("message"));
ok($text =~ /The 'sel-tmp' tag has been added to bug $bug1_id/, "Bug added to 'sel-tmp' tag");
$sel->click_ok("link=sel-tmp");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->is_text_present_ok("Tags: sel-tmp");
$sel->is_text_present_ok("One bug found");

# File another bug in the 'TestProduct' product.

file_bug_in_product($sel, 'TestProduct');
$sel->value_is("cc", "");
$sel->type_ok("short_desc", "My second bug");
$sel->type_ok("comment", "Still not in the CC list");
$sel->click_ok("commit");
$sel->wait_for_page_to_load(WAIT_TIME);
my $bug2_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
$sel->is_text_present_ok('has been added to the database', "Bug $bug2_id created");
$sel->value_is("addselfcc", "off");

# Add another bug to the tag.

$sel->select_ok("lob_action", "label=Add");
$sel->select_ok("lob_oldqueryname", "label=sel-tmp");
$sel->type_ok("bug_ids", $bug2_id);
$sel->click_ok("commit_list_of_bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Tag Updated");
$text = trim($sel->get_text("message"));
ok($text =~ /The 'sel-tmp' tag has been added to bug $bug2_id/, "Bug added to 'sel-tmp' tag");
$sel->click_ok("link=sel-tmp");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("Tags: sel-tmp");
$sel->is_text_present_ok("2 bugs found");
$sel->click_ok("link=$bug1_id");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->type_ok("comment", "The next bug I should see is this one.");
$sel->click_ok("commit");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");

$sel->click_ok("editme_action");
$sel->value_is("short_desc", "First bug created");
$sel->is_text_present_ok("The next bug I should see is this one.");

# Remove the tag from all bugs.

$sel->open_ok("/$config->{bugzilla_installation}/buglist.cgi?tag=sel-tmp", undef, "List 'sel-tmp' bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("Tags: sel-tmp");
$sel->click_ok("link=$bug1_id");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->select_ok("lob_action", "label=Remove");
$sel->select_ok("lob_oldqueryname", "label=sel-tmp");
$sel->type_ok("bug_ids", $bug1_id);
$sel->click_ok("commit_list_of_bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Tag Updated");
$text = trim($sel->get_text("message"));
ok($text =~ /The 'sel-tmp' tag has been removed from bug $bug1_id/, "Bug removed from 'sel-tmp' tag");
$sel->click_ok("link=sel-tmp");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("Tags: sel-tmp");
$sel->click_ok("link=$bug2_id");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_like(qr/^$bug2_id /);
$sel->select_ok("lob_action", "label=Remove");
$sel->select_ok("lob_oldqueryname", "label=sel-tmp");
$sel->type_ok("bug_ids", $bug2_id);
$sel->click_ok("commit_list_of_bugs");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Tag Updated");
$text = trim($sel->get_text("message"));
ok($text =~ /The 'sel-tmp' tag has been removed from bug $bug2_id/, "Bug removed from 'sel-tmp' tag");
$sel->click_ok("link=sel-tmp");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("Tags: sel-tmp");
$sel->is_text_present_ok("Zarro Boogs found");
logout($sel);

# Edit own user preferences, now as an unprivileged user.

log_in($sel, $config, 'unprivileged');
$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=General Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
ok(!$sel->is_element_present("skin"), "The 'skin' user preference is not present");
$sel->select_ok("state_addselfcc", "label=Always");
$sel->select_ok("post_bug_submit_action", "label=Show next bug in my list");
$sel->select_ok("per_bug_queries", "label=Off");
ok(!$sel->is_element_present("zoom_textareas"), "The 'zoom_textareas' user preference is not present");
$sel->click_ok("update");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("User Preferences");

ok(!$sel->is_element_present("lob_action"), "Element 1/3 for tags is not displayed");
ok(!$sel->is_element_present("lob_newqueryname"), "Element 2/3 for tags is not displayed");
ok(!$sel->is_element_present("commit_list_of_bugs"), "Element 3/3 for tags is not displayed");

# Create a new search named 'my_list'.

open_advanced_search_page($sel);
$sel->remove_all_selections_ok("product");
$sel->add_selection_ok("product", "TestProduct");
$sel->remove_all_selections_ok("bug_status");
$sel->select_ok("bug_id_type", "label=only included in");
$sel->type_ok("bug_id", "$bug1_id , $bug2_id");
$sel->select_ok("order", "label=Bug Number");
$sel->click_ok("Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("2 bugs found");
$sel->type_ok("save_newqueryname", "my_list");
$sel->click_ok("remember");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Search created");
$text = trim($sel->get_text("message"));
ok($text =~ /OK, you have a new search named my_list./, "New saved search 'my_list' has been created");

# Editing bugs should follow user preferences.

$sel->click_ok("link=my_list");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: my_list");
$sel->click_ok("link=$bug1_id");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_like(qr/^$bug1_id .* First bug created/);
$sel->value_is("addselfcc", "on");
$sel->type_ok("comment", "I should be CC'ed and then I should see the next bug.");
$sel->click_ok("commit");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->is_text_present_ok("The next bug in your list is bug $bug2_id");
ok(!$sel->is_text_present("I should see the next bug"), "The updated bug is no longer displayed");
# The user has no privs, so the short_desc field is not present.
$sel->is_text_present_ok("My second bug");
$sel->value_is("addselfcc", "on");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_like(qr/^$bug1_id .* First bug created/);
$sel->is_text_present_ok("1 user including you");

# Delete the saved search and log out.

$sel->click_ok("link=my_list");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: my_list");
$sel->click_ok("link=Forget Search 'my_list'");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Search is gone");
$text = trim($sel->get_text("message"));
ok($text =~ /OK, the my_list search is gone/, "The saved search 'my_list' has been deleted");
logout($sel);
