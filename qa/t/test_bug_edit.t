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
set_parameters($sel, { "Bug Fields" => {"usestatuswhiteboard-on" => undef} });

# Clear the saved search, in case this test didn't complete previously.
if ($sel->is_text_present("My bugs from QA_Selenium")) {
    $sel->click_ok("link=My bugs from QA_Selenium");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Bug List: My bugs from QA_Selenium");
    $sel->click_ok("link=Forget Search 'My bugs from QA_Selenium'");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Search is gone");
    $sel->is_text_present_ok("OK, the My bugs from QA_Selenium search is gone");
}

# Just in case the test failed before completion previously, reset the CANEDIT bit.
go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("link=Master");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Group: Master");
my $group_url = $sel->get_location();
$group_url =~ /group=(\d+)$/;
my $master_gid = $1;

clear_canedit_on_testproduct($sel, $master_gid);
logout($sel);

# First create a bug.

log_in($sel, $config, 'QA_Selenium_TEST');
file_bug_in_product($sel, 'TestProduct');
$sel->select_ok("bug_severity", "label=critical");
$sel->type_ok("short_desc", "Test bug editing");
$sel->type_ok("comment", "ploc");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
my $bug1_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
$sel->is_text_present_ok('has been added to the database', "Bug $bug1_id created");

# Now edit field values of the bug you just filed.

$sel->select_ok("rep_platform", "label=Other");
$sel->select_ok("op_sys", "label=Other");
$sel->select_ok("priority", "label=Highest");
$sel->select_ok("bug_severity", "label=blocker");
$sel->type_ok("bug_file_loc", "foo.cgi?action=bar");
$sel->type_ok("status_whiteboard", "[Selenium was here]");
$sel->type_ok("comment", "new comment from me :)");
$sel->select_ok("bug_status", "label=RESOLVED");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");

# Now move the bug into another product, which has a mandatory group.

$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->select_ok("product", "label=QA-Selenium-TEST");
$sel->type_ok("comment", "moving to QA-Selenium-TEST");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Verify New Product Details...");
$sel->select_ok("component", "label=QA-Selenium-TEST");
$sel->is_element_present_ok('//input[@type="checkbox" and @name="groups" and @value="QA-Selenium-TEST"]');
ok(!$sel->is_editable('//input[@type="checkbox" and @name="groups" and @value="QA-Selenium-TEST"]'), "QA-Selenium-TEST group not editable");
$sel->is_checked_ok('//input[@type="checkbox" and @name="groups" and @value="QA-Selenium-TEST"]', "QA-Selenium-TEST group is selected");
$sel->click_ok("change_product");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->select_ok("bug_severity", "label=normal");
$sel->select_ok("priority", "label=High");
$sel->select_ok("rep_platform", "label=All");
$sel->select_ok("op_sys", "label=All");
$sel->click_ok("cc_edit_area_showhide");
$sel->type_ok("newcc", $config->{admin_user_login});
$sel->type_ok("comment", "Unchecking the reporter_accessible checkbox");
# This checkbox is checked by default.
$sel->click_ok("reporter_accessible");
$sel->select_ok("bug_status", "label=VERIFIED");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->type_ok("comment", "I am the reporter, but I can see the bug anyway as I belong to the mandatory group");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
logout($sel);

# The admin is not in the mandatory group, but he has been CC'ed,
# so he can view and edit the bug (as he has editbugs privs by inheritance).

log_in($sel, $config, 'admin');
go_to_bug($sel, $bug1_id);
$sel->select_ok("bug_severity", "label=blocker");
$sel->select_ok("priority", "label=Highest");
$sel->type_ok("status_whiteboard", "[Selenium was here][admin too]");
$sel->select_ok("bug_status", "label=CONFIRMED");
$sel->click_ok("bz_assignee_edit_action");
$sel->type_ok("assigned_to", $config->{admin_user_login});
$sel->type_ok("comment", "I have editbugs privs. Taking!");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");

$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->click_ok("cc_edit_area_showhide");
$sel->type_ok("newcc", $config->{unprivileged_user_login});
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
logout($sel);

# The powerless user can see the restricted bug, as he has been CC'ed.

log_in($sel, $config, 'unprivileged');
go_to_bug($sel, $bug1_id);
$sel->is_text_present_ok("I have editbugs privs. Taking!");
logout($sel);

# Now turn off cclist_accessible, which will prevent
# the powerless user to see the bug again.

log_in($sel, $config, 'admin');
go_to_bug($sel, $bug1_id);
$sel->click_ok("cclist_accessible");
$sel->type_ok("comment", "I am allowed to turn off cclist_accessible despite not being in the mandatory group");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
logout($sel);

# The powerless user cannot see the restricted bug anymore.

log_in($sel, $config, 'unprivileged');
$sel->type_ok("quicksearch_top", $bug1_id);
$sel->submit("header-search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Access Denied");
$sel->is_text_present_ok("You are not authorized to access bug $bug1_id");
logout($sel);

# Move the bug back to TestProduct, which has no group restrictions.

log_in($sel, $config, 'admin');
go_to_bug($sel, $bug1_id);
$sel->select_ok("product", "label=TestProduct");
# When selecting a new product, Bugzilla tries to reassign the bug by default,
# so we have to uncheck it.
$sel->click_ok("set_default_assignee");
$sel->uncheck_ok("set_default_assignee");
$sel->type_ok("comment", "-> Moving back to Testproduct.");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Verify New Product Details...");
$sel->select_ok("component", "label=TestComponent");
$sel->is_text_present_ok("These groups are not legal for the 'TestProduct' product or you are not allowed to restrict bugs to these groups");
$sel->is_element_present_ok('//input[@type="checkbox" and @name="groups" and @value="QA-Selenium-TEST"]');
ok(!$sel->is_editable('//input[@type="checkbox" and @name="groups" and @value="QA-Selenium-TEST"]'), "QA-Selenium-TEST group not editable");
ok(!$sel->is_checked('//input[@type="checkbox" and @name="groups" and @value="QA-Selenium-TEST"]'), "QA-Selenium-TEST group not selected");
$sel->is_element_present_ok('//input[@type="checkbox" and @name="groups" and @value="Master"]');
$sel->is_editable_ok('//input[@type="checkbox" and @name="groups" and @value="Master"]', "Master group is editable");
ok(!$sel->is_checked('//input[@type="checkbox" and @name="groups" and @value="Master"]'), "Master group not selected by default");
$sel->click_ok("change_product");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->click_ok("cclist_accessible");
$sel->type_ok("comment", "I am allowed to turn off cclist_accessible despite not being in the mandatory group");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
logout($sel);

# The unprivileged user can view the bug again, but cannot
# edit it, except adding comments.

log_in($sel, $config, 'unprivileged');
go_to_bug($sel, $bug1_id);
$sel->type_ok("comment", "I have no privs, I can only comment (and remove people from the CC list)");
ok(!$sel->is_element_present('//select[@name="product"]'), "Product field not editable");
ok(!$sel->is_element_present('//select[@name="bug_severity"]'), "Severity field not editable");
ok(!$sel->is_element_present('//select[@name="priority"]'), "Priority field not editable");
ok(!$sel->is_element_present('//select[@name="op_sys"]'), "OS field not editable");
ok(!$sel->is_element_present('//select[@name="rep_platform"]'), "Hardware field not editable");
$sel->click_ok("cc_edit_area_showhide");
$sel->add_selection_ok("cc", "label=" . $config->{admin_user_login});
$sel->click_ok("removecc");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
logout($sel);

# Now let's test the CANEDIT bit.

log_in($sel, $config, 'admin');
edit_product($sel, "TestProduct");
$sel->click_ok("link=Edit Group Access Controls:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Group Controls for TestProduct");
$sel->check_ok("canedit_$master_gid");
$sel->click_ok("submit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Update group access controls for TestProduct");

# The user is in the master group, so he can comment.

go_to_bug($sel, $bug1_id);
$sel->type_ok("comment", "Do nothing except adding a comment...");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
logout($sel);

# This user is not in the master group, so he cannot comment.

log_in($sel, $config, 'QA_Selenium_TEST');
go_to_bug($sel, $bug1_id);
$sel->type_ok("comment", "Just a comment too...");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Edit Access Denied");
$sel->is_text_present_ok("You are not permitted to edit bugs in product TestProduct.");
logout($sel);

# Test searches and "format for printing".

log_in($sel, $config, 'admin');
open_advanced_search_page($sel);
$sel->remove_all_selections_ok("product");
$sel->add_selection_ok("product", "TestProduct");
$sel->remove_all_selections_ok("bug_status");
$sel->remove_all_selections_ok("resolution");
$sel->is_checked_ok("emailassigned_to1");
$sel->select_ok("emailtype1", "label=is");
$sel->type_ok("email1", $config->{admin_user_login});
$sel->check_ok("emailassigned_to2");
$sel->check_ok("emailqa_contact2");
$sel->check_ok("emailcc2");
$sel->select_ok("emailtype2", "label=is");
$sel->type_ok("email2", $config->{QA_Selenium_TEST_user_login});
$sel->click_ok("Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");

$sel->is_text_present_ok("One bug found.");
$sel->type_ok("save_newqueryname", "My bugs from QA_Selenium");
$sel->click_ok("remember");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search created");
$sel->is_text_present_ok("OK, you have a new search named My bugs from QA_Selenium.");
$sel->click_ok("link=My bugs from QA_Selenium");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: My bugs from QA_Selenium");
$sel->click_ok("long_format");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Full Text Bug Listing");
$sel->is_text_present_ok("Bug $bug1_id");
$sel->is_text_present_ok("Status: CONFIRMED");
$sel->is_text_present_ok("Reporter: QA-Selenium-TEST <$config->{QA_Selenium_TEST_user_login}>");
$sel->is_text_present_ok("Assignee: QA Admin <$config->{admin_user_login}>");
$sel->is_text_present_ok("Severity: blocker");
$sel->is_text_present_ok("Priority: Highest");
$sel->is_text_present_ok("I have no privs, I can only comment");
logout($sel);

# Let's create a 2nd bug by this user so that we can test mass-change
# using the saved search the admin just created.

log_in($sel, $config, 'QA_Selenium_TEST');
file_bug_in_product($sel, 'TestProduct');
$sel->select_ok("bug_severity", "label=blocker");
$sel->type_ok("short_desc", "New bug from me");
# We turned on the CANEDIT bit for TestProduct.
$sel->type_ok("comment", "I can enter a new bug, but not edit it, right?");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
my $bug2_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
$sel->is_text_present_ok('has been added to the database', "Bug $bug2_id created");

# Clicking the "Back" button and resubmitting the form again should trigger a suspicous action error.

$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Enter Bug: TestProduct");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Suspicious Action");
$sel->is_text_present_ok("you have no valid token for the create_bug action");
$sel->click_ok('//input[@value="Confirm Changes"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
$sel->type_ok("comment", "New comment not allowed");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Edit Access Denied");
$sel->is_text_present_ok("You are not permitted to edit bugs in product TestProduct.");
logout($sel);

# Reassign the newly created bug to the admin.

log_in($sel, $config, 'admin');
go_to_bug($sel, $bug2_id);
$sel->click_ok("bz_assignee_edit_action");
$sel->type_ok("assigned_to", $config->{admin_user_login});
$sel->type_ok("comment", "Taking!");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug2_id");

# Test mass-change.

$sel->click_ok("link=My bugs from QA_Selenium");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: My bugs from QA_Selenium");
$sel->is_text_present_ok("2 bugs found");
$sel->click_ok("link=Change Several Bugs at Once");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->click_ok("check_all");
$sel->type_ok("comment", 'Mass change"');
$sel->select_ok("bug_status", "label=RESOLVED");
$sel->select_ok("resolution", "label=WORKSFORME");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bugs processed");

$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/$bug1_id /);
$sel->selected_label_is("resolution", "WORKSFORME");
$sel->select_ok("resolution", "label=INVALID");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");

$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/$bug1_id /);
$sel->selected_label_is("resolution", "INVALID");

$sel->click_ok("link=History");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Changes made to bug $bug1_id");
$sel->is_text_present_ok("URL foo.cgi?action=bar");
$sel->is_text_present_ok("Severity critical blocker");
$sel->is_text_present_ok("Whiteboard [Selenium was here] [Selenium was here][admin too]");
$sel->is_text_present_ok("Product QA-Selenium-TEST TestProduct");
$sel->is_text_present_ok("Status CONFIRMED RESOLVED");

# Last step: move bugs to another DB, if the extension is enabled.

# if ($config->{test_extensions}) {
#     set_parameters($sel, { "Bug Moving" => {"move-to-url"     => {type => "text", value => 'http://www.foo.com/'},
#                                             "move-to-address" => {type => "text", value => 'import@foo.com'},
#                                             "movers"          => {type => "text", value => $config->{admin_user_login}}
#                                            }
#                          });
#
#     # Mass-move has been removed, see 581690.
#     # Restore these tests once this bug is fixed.
#     # $sel->click_ok("link=My bugs from QA_Selenium");
#     # $sel->wait_for_page_to_load_ok(WAIT_TIME);
#     # $sel->title_is("Bug List: My bugs from QA_Selenium");
#     # $sel->is_text_present_ok("2 bugs found");
#     # $sel->click_ok("link=Change Several Bugs at Once");
#     # $sel->wait_for_page_to_load_ok(WAIT_TIME);
#     # $sel->title_is("Bug List");
#     # $sel->click_ok("check_all");
#     # $sel->type_ok("comment", "-> moved");
#     # $sel->click_ok('oldbugmove');
#     # $sel->wait_for_page_to_load_ok(WAIT_TIME);
#     # $sel->title_is("Bugs processed");
#     # $sel->is_text_present_ok("Bug $bug1_id has been moved to another database");
#     # $sel->is_text_present_ok("Bug $bug2_id has been moved to another database");
#     # $sel->click_ok("link=Bug $bug2_id");
#     # $sel->wait_for_page_to_load_ok(WAIT_TIME);
#     # $sel->title_like(qr/^$bug2_id/);
#     # $sel->selected_label_is("resolution", "MOVED");
#
#     go_to_bug($sel, $bug2_id);
#     $sel->click_ok('oldbugmove');
#     $sel->wait_for_page_to_load_ok(WAIT_TIME);
#     $sel->is_text_present_ok("Changes submitted for bug $bug2_id");
#     $sel->click_ok("link=bug $bug2_id");
#     $sel->wait_for_page_to_load_ok(WAIT_TIME);
#     $sel->title_like(qr/$bug2_id /);
#     $sel->selected_label_is("resolution", "MOVED");
#     $sel->is_text_present_ok("Bug moved to http://www.foo.com/.");
#
#     # Disable bug moving again.
#     set_parameters($sel, { "Bug Moving" => {"movers" => {type => "text", value => ""}} });
# }

# Make sure token checks are working correctly for single bug editing and mass change,
# first with no token, then with an invalid token.

foreach my $params (["no_token_single_bug", ""], ["invalid_token_single_bug", "&token=1"]) {
    my ($comment, $token) = @$params;
    $sel->open_ok("/$config->{bugzilla_installation}/process_bug.cgi?id=$bug1_id&comment=$comment$token",
                  undef, "Edit a single bug with " . ($token ? "an invalid" : "no") . " token");
    $sel->title_is("Suspicious Action");
    $sel->is_text_present_ok($token ? "an invalid token" : "web browser directly");
    $sel->click_ok("confirm");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->is_text_present_ok("Changes submitted for bug $bug1_id");
    $sel->click_ok("link=bug $bug1_id");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_like(qr/^$bug1_id /);
    $sel->is_text_present_ok($comment);
}

foreach my $params (["no_token_mass_change", ""], ["invalid_token_mass_change", "&token=1"]) {
    my ($comment, $token) = @$params;
    $sel->open_ok("/$config->{bugzilla_installation}/process_bug.cgi?id_$bug1_id=1&id_$bug2_id=1&comment=$comment$token",
                  undef, "Mass change with " . ($token ? "an invalid" : "no") . " token");
    $sel->title_is("Suspicious Action");
    $sel->is_text_present_ok("no valid token for the buglist_mass_change action");
    $sel->click_ok("confirm");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Bugs processed");
    foreach my $bug_id ($bug1_id, $bug2_id) {
        $sel->click_ok("link=bug $bug_id");
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
        $sel->title_like(qr/^$bug_id /);
        $sel->is_text_present_ok($comment);
        next if $bug_id == $bug2_id;
        $sel->go_back_ok();
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
        $sel->title_is("Bugs processed");
    }
}

# Now move these bugs out of our radar.

$sel->click_ok("link=My bugs from QA_Selenium");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: My bugs from QA_Selenium");
$sel->is_text_present_ok("2 bugs found");
$sel->click_ok("link=Change Several Bugs at Once");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->click_ok("check_all");
$sel->type_ok("comment", "Reassigning to the reporter");
$sel->type_ok("assigned_to", $config->{QA_Selenium_TEST_user_login});
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bugs processed");

# Now delete the saved search.

$sel->click_ok("link=My bugs from QA_Selenium");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: My bugs from QA_Selenium");
$sel->click_ok("link=Forget Search 'My bugs from QA_Selenium'");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search is gone");
$sel->is_text_present_ok("OK, the My bugs from QA_Selenium search is gone");

# Reset the CANEDIT bit. We want it to be turned off by default.
clear_canedit_on_testproduct($sel, $master_gid);
logout($sel);

sub clear_canedit_on_testproduct {
    my ($sel, $master_gid) = @_;

    edit_product($sel, "TestProduct");
    $sel->click_ok("link=Edit Group Access Controls:");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Edit Group Controls for TestProduct");
    $sel->uncheck_ok("canedit_$master_gid");
    $sel->click_ok("submit");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Update group access controls for TestProduct");
}
