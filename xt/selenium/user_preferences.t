# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.14.0;
use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../lib", "$RealBin/../../local/lib/perl5";

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
$sel->uncheck_ok("zoom_textareas-enabled");
$sel->select_ok("zoom_textareas", "label=Off");
$sel->click_ok("update");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Default Preferences");

# Update own user preferences. Some of them are not editable.

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("General Preferences");
ok(!$sel->is_editable("skin"), "The 'skin' user preference is not editable");
$sel->select_ok("state_addselfcc", "label=Site Default (Never)");
$sel->select_ok("post_bug_submit_action",
  "label=Site Default (Show the updated bug)");
ok(!$sel->is_editable("zoom_textareas"),
  "The 'zoom_textareas' user preference is not editable");
$sel->click_ok("update");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("General Preferences");

# File a bug in the 'TestProduct' product. The form fields must follow user prefs.

file_bug_in_product($sel, 'TestProduct');
$sel->value_is("cc", "");
my $bug_summary = "First bug created";
$sel->type_ok("short_desc", $bug_summary);
$sel->type_ok("comment",    "I'm not in the CC list.");
my $bug1_id = create_bug($sel, $bug_summary);

$sel->value_is("addselfcc", "off");
$sel->type_ok("tag", "sel-tmp");
$sel->select_ok("bug_status", "label=IN_PROGRESS");
edit_bug($sel, $bug1_id, $bug_summary);
$sel->click_ok("summary_edit_action");
$sel->value_is("short_desc", $bug_summary);
$sel->value_is("addselfcc",  "off");

# Create a saved search for the 'sel-tmp' tag.

$sel->type_ok("quicksearch_top", "tag:sel-tmp");
$sel->click_ok("find_top");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: tag:sel-tmp");
$sel->type_ok("save_newqueryname", "sel-tmp");
$sel->click_ok("remember");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search created");
$sel->is_text_present_ok("OK, you have a new search named sel-tmp");

# Leave this page to avoid clicking on the wrong 'sel-tmp' link.
go_to_home($sel, $config);
$sel->click_ok("link=sel-tmp");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: sel-tmp");
$sel->is_text_present_ok("One bug found");

# File another bug in the 'TestProduct' product.

file_bug_in_product($sel, 'TestProduct');
$sel->value_is("cc", "");
my $bug_summary2 = "My second bug";
$sel->type_ok("short_desc", $bug_summary2);
$sel->type_ok("comment",    "Still not in the CC list");
my $bug2_id = create_bug($sel, $bug_summary2);
$sel->value_is("addselfcc", "off");
$sel->type_ok("tag", "sel-tmp");
edit_bug($sel, $bug2_id, $bug_summary2);

$sel->click_ok("link=sel-tmp");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: sel-tmp");
$sel->is_text_present_ok("2 bugs found");
$sel->click_ok("link=$bug1_id");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->type_ok("comment", "The next bug I should see is this one.");
edit_bug($sel, $bug1_id, $bug_summary);
$sel->click_ok("summary_edit_action");
$sel->value_is("short_desc", "First bug created");
$sel->is_text_present_ok("The next bug I should see is this one.");

# Remove the saved search. The tag itself still exists.

$sel->click_ok("link=sel-tmp");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: sel-tmp");
$sel->click_ok("forget_search");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Search is gone");
$sel->is_text_present_ok("OK, the sel-tmp search is gone");

# Remove the tag from bugs.

$sel->type_ok("quicksearch_top", "tag:sel-tmp");
$sel->click_ok("find_top");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("2 bugs found");

# We cannot remove tags from several bugs at once (bug 791584).
go_to_bug($sel, $bug1_id);
$sel->type_ok("tag", "");
edit_bug($sel, $bug1_id, $bug_summary);

go_to_bug($sel, $bug2_id);
$sel->type_ok("tag", "");
edit_bug($sel, $bug2_id, $bug_summary2);

$sel->type_ok("quicksearch_top", "tag:sel-tmp");
$sel->click_ok("find_top");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("Zarro Boogs found");
logout($sel);

# Edit own user preferences, now as an unprivileged user.

log_in($sel, $config, 'unprivileged');
$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("General Preferences");
ok(!$sel->is_editable("skin"), "The 'skin' user preference is not editable");
$sel->select_ok("state_addselfcc",        "label=Always");
$sel->select_ok("post_bug_submit_action", "label=Show next bug in my list");
ok(!$sel->is_editable("zoom_textareas"),
  "The 'zoom_textareas' user preference is not editable");
$sel->click_ok("update");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("General Preferences");

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
$sel->is_text_present_ok("OK, you have a new search named my_list");

# Editing bugs should follow user preferences.

$sel->click_ok("link=my_list");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: my_list");
$sel->click_ok("link=$bug1_id");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->value_is("addselfcc", "on");
$sel->type_ok("comment",
  "I should be CC'ed and then I should see the next bug.");
edit_bug($sel, $bug2_id, $bug_summary2);
$sel->is_text_present_ok("The next bug in your list is bug $bug2_id");
ok(!$sel->is_text_present("I should see the next bug"),
  "The updated bug is no longer displayed");

# The user has no privs, so the short_desc field is not present.
$sel->is_text_present("short_desc", "My second bug");
$sel->value_is("addselfcc", "on");
$sel->click_ok("link=$bug1_id");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->is_text_present("1 user including you");

# Delete the saved search and log out.

$sel->click_ok("link=my_list");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Bug List: my_list");
$sel->click_ok("forget_search");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Search is gone");
$sel->is_text_present_ok("OK, the my_list search is gone");
logout($sel);

# Restore default user preferences.

log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok("link=Default Preferences");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Default Preferences");
$sel->check_ok("skin-enabled");
$sel->uncheck_ok("post_bug_submit_action-enabled");
$sel->select_ok("post_bug_submit_action", "label=Do Nothing");
$sel->click_ok("update");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Default Preferences");
logout($sel);
