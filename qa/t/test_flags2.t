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

################################################################
# 2nd script about flags. This one is focused on flag behavior #
# when moving a bug from one product/component to another one. #
################################################################

# We have to upload files from the local computer. This requires
# chrome privileges.
my ($sel, $config) = get_selenium(CHROME_MODE);

# Start by creating a flag type for bugs.

log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok("link=Flags");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Administer Flag Types");
$sel->click_ok("link=Create Flag Type for Bugs");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->type_ok("name", "selenium");
$sel->type_ok("description", "Available in TestProduct and Another Product/c1");
$sel->add_selection_ok("inclusion_to_remove", "label=__Any__:__Any__");
$sel->click_ok("categoryAction-removeInclusion");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->select_ok("product", "label=TestProduct");
$sel->selected_label_is("component", "__Any__");
$sel->click_ok("categoryAction-include");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->select_ok("product", "label=Another Product");
$sel->select_ok("component", "label=c1");
$sel->click_ok("categoryAction-include");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");

# This flag type must have a higher sortkey than the one we will create later.
# The reason is that link=selenium will catch the first link with this name in
# the UI, so when the second flag type with this name is created, we have to
# catch it, not this one (which will be unique for now, so no worry to find it).

$sel->type_ok("sortkey", 100);
$sel->value_is("is_active", "on");
$sel->value_is("is_requestable", "on");
$sel->click_ok("is_multiplicable");
$sel->value_is("is_multiplicable", "off");
$sel->select_ok("grant_group", "label=editbugs");
$sel->select_ok("request_group", "label=canconfirm");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'selenium' Created");
$sel->is_text_present_ok("The flag type selenium has been created.");

# Store the flag type ID.

$sel->click_ok("link=selenium");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
my $flag_url = $sel->get_location();
$flag_url =~ /id=(\d+)/;
my $flagtype1_id = $1;

# Now create a flag type for attachments in 'Another Product'.

$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->click_ok("link=Create Flag Type For Attachments");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Attachments");
$sel->type_ok("name", "selenium_review");
$sel->type_ok("description", "Review flag used by Selenium");
$sel->add_selection_ok("inclusion_to_remove", "label=__Any__:__Any__");
$sel->click_ok("categoryAction-removeInclusion");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Attachments");
$sel->select_ok("product", "label=Another Product");
$sel->click_ok("categoryAction-include");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Attachments");
$sel->type_ok("sortkey", 100);
$sel->value_is("is_active", "on");
$sel->value_is("is_requestable", "on");
$sel->click_ok("is_multiplicable");
$sel->value_is("is_multiplicable", "off");
$sel->selected_label_is("grant_group", "(no group)");
$sel->selected_label_is("request_group", "(no group)");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'selenium_review' Created");
$sel->is_text_present_ok("The flag type selenium_review has been created.");

# Store the flag type ID.

$sel->click_ok("link=selenium_review");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$flag_url = $sel->get_location();
$flag_url =~ /id=(\d+)/;
my $aflagtype1_id = $1;

# Create a 2nd flag type for attachments, with the same name
# as the 1st one, but now *excluded* from 'Another Product'.

$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->click_ok("link=Create Flag Type For Attachments");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->type_ok("name", "selenium_review");
$sel->type_ok("description", "Another review flag used by Selenium");
$sel->select_ok("product", "label=Another Product");
$sel->click_ok("categoryAction-include");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Attachments");
$sel->type_ok("sortkey", 50);
$sel->value_is("is_active", "on");
$sel->value_is("is_requestable", "on");
$sel->value_is("is_multiplicable", "on");
$sel->select_ok("grant_group", "label=editbugs");
$sel->select_ok("request_group", "label=canconfirm");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'selenium_review' Created");

# Store the flag type ID.

$sel->click_ok("link=selenium_review");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$flag_url = $sel->get_location();
$flag_url =~ /id=(\d+)/;
my $aflagtype2_id = $1;

# We are done with the admin tasks. Now play with flags in bugs.

file_bug_in_product($sel, 'TestProduct');
$sel->click_ok('//input[@value="Set bug flags"]');
$sel->select_ok("flag_type-$flagtype1_id", "label=+");
$sel->type_ok("short_desc", "The selenium flag should be kept on product change");
$sel->type_ok("comment", "pom");
$sel->click_ok('//input[@value="Add an attachment"]');
$sel->type_ok("data", $config->{attachment_file});
$sel->type_ok("description", "small patch");
$sel->value_is("ispatch", "on");
ok(!$sel->is_element_present("flag_type-$aflagtype1_id"), "Flag type $aflagtype1_id not available in TestProduct");
$sel->select_ok("flag_type-$aflagtype2_id", "label=-");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');

# Store the bug and flag IDs.

my $bug1_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
$sel->click_ok("link=Bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->is_text_present_ok("$config->{admin_user_nick}: selenium");
my $flag1_id = $sel->get_attribute('//select[@title="Available in TestProduct and Another Product/c1"]@id');
$flag1_id =~ s/flag-//;
$sel->selected_label_is("flag-$flag1_id", "+");
$sel->is_text_present_ok("$config->{admin_user_nick}: selenium_review-");

# Now move the bug into the 'Another Product' product.
# Both the bug and attachment flags should survive.

$sel->select_ok("product", "label=Another Product");
$sel->type_ok("comment", "Moving to Another Product / c1. The flag should be preserved.");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Verify New Product Details...");
$sel->select_ok("component", "label=c1");
$sel->click_ok("change_product");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->selected_label_is("flag-$flag1_id", "+");
$sel->is_text_present_ok("$config->{admin_user_nick}: selenium_review-");

# Now moving the bug into the c2 component. The bug flag
# won't survive, but the attachment flag should.

$sel->type_ok("comment", "Moving to c2. The selenium flag will be deleted.");
$sel->select_ok("component", "label=c2");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
ok(!$sel->is_element_present("flag-$flag1_id"), "The selenium bug flag didn't survive");
ok(!$sel->is_element_present("flag_type-$flagtype1_id"), "The selenium flag type doesn't exist");
$sel->is_text_present_ok("$config->{admin_user_nick}: selenium_review-");

# File a bug in 'Another Product / c2' and assign it
# to a powerless user, so that he can move it later.

file_bug_in_product($sel, 'Another Product');
$sel->click_ok('//input[@value="Set bug flags"]');
$sel->select_ok("component", "label=c2");
$sel->type_ok("assigned_to", $config->{unprivileged_user_login});
ok(!$sel->is_editable("flag_type-$flagtype1_id"), "The selenium bug flag type is displayed but not selectable");
$sel->select_ok("component", "label=c1");
$sel->is_editable_ok("flag_type-$flagtype1_id", "The selenium bug flag type is not selectable");
$sel->select_ok("flag_type-$flagtype1_id", "label=?");
$sel->type_ok("short_desc", "Create a new selenium flag for c2");
$sel->type_ok("comment", ".");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');

# Store the bug and flag IDs.

my $bug2_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
$sel->click_ok("link=Bug $bug2_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug2_id /);
$sel->is_text_present_ok("$config->{admin_user_nick}: selenium");
my $flag2_id = $sel->get_attribute('//select[@title="Available in TestProduct and Another Product/c1"]@id');
$flag2_id =~ s/flag-//;
$sel->selected_label_is("flag-$flag2_id", '?');

# Create a 2nd bug flag type, again named 'selenium', but now
# for the 'Another Product / c2' component only.

go_to_admin($sel);
$sel->click_ok("link=Flags");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Administer Flag Types");
$sel->click_ok("link=Create Flag Type for Bugs");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->type_ok("name", "selenium");
$sel->type_ok("description", "Another flag with the selenium name");
$sel->add_selection_ok("inclusion_to_remove", "label=__Any__:__Any__");
$sel->click_ok("categoryAction-removeInclusion");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->select_ok("product", "label=Another Product");
$sel->select_ok("component", "label=c2");
$sel->click_ok("categoryAction-include");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->type_ok("sortkey", 50);
$sel->value_is("is_active", "on");
$sel->value_is("is_requestable", "on");
$sel->value_is("is_multiplicable", "on");
$sel->selected_label_is("grant_group", "(no group)");
$sel->selected_label_is("request_group", "(no group)");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'selenium' Created");

# Store the flag type ID.

$sel->click_ok("link=selenium");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$flag_url = $sel->get_location();
$flag_url =~ /id=(\d+)/;
my $flagtype2_id = $1;

# Now move the bug from c1 into c2. The bug flag should survive.

go_to_bug($sel, $bug2_id);
$sel->select_ok("component", "label=c2");
$sel->type_ok("comment", "The selenium flag should be preserved.");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug2_id");
$sel->click_ok("link=bug $bug2_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug2_id /);
$sel->selected_label_is("flag-$flag2_id", '?');
ok(!$sel->is_element_present("flag_type-$flagtype1_id"), "Flag type not available in c2");
$sel->is_element_present_ok("flag_type-$flagtype2_id");
logout($sel);

# Powerless users can edit the 'selenium' flag being in c2.

log_in($sel, $config, 'unprivileged');
go_to_bug($sel, $bug2_id);
$sel->select_ok("flag-$flag2_id", "label=+");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug2_id");
$sel->click_ok("link=bug $bug2_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug2_id /);
$sel->selected_label_is("flag-$flag2_id", "+");

# But moving the bug into TestProduct will delete the flag
# as the flag setter is not in the editbugs group.

$sel->select_ok("product", "label=TestProduct");
$sel->type_ok("comment", "selenium flag will be lost. I don't have editbugs privs.");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Verify New Product Details...");
$sel->click_ok("change_product");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug2_id");
$sel->click_ok("link=bug $bug2_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug2_id /);
ok(!$sel->is_element_present("flag-$flag2_id"), "Flag $flag2_id deleted");
ok(!$sel->is_editable("flag_type-$flagtype1_id"), "Flag type 'selenium' not editable by powerless users");
ok(!$sel->is_element_present("flag_type-$flagtype2_id"), "Flag type not available in c1");
logout($sel);

# Time to delete created flag types.

log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok("link=Flags");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Administer Flag Types");

foreach my $flagtype ([$flagtype1_id, "selenium"], [$flagtype2_id, "selenium"],
                      [$aflagtype1_id, "selenium_review"], [$aflagtype2_id, "selenium_review"])
{
    my $flag_id = $flagtype->[0];
    my $flag_name = $flagtype->[1];
    $sel->click_ok("//a[\@href='editflagtypes.cgi?action=confirmdelete&id=$flag_id']");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Confirm Deletion of Flag Type '$flag_name'");
    $sel->click_ok("link=Yes, delete");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Flag Type '$flag_name' Deleted");
    my $msg = trim($sel->get_text("message"));
    ok($msg eq "The flag type $flag_name has been deleted.", "Flag type $flag_name deleted");
}
logout($sel);
