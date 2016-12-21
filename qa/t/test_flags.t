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

# We have to upload files from the local computer. This requires
# chrome privileges.
my ($sel, $config) = get_selenium(CHROME_MODE);

# First create a flag type for bugs.

log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok("link=Flags");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Administer Flag Types");
$sel->click_ok("link=Create Flag Type for Bugs");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->type_ok("name", "SeleniumBugFlag1Test");
$sel->type_ok("description", "bugflag1");
$sel->select_ok("product", "label=TestProduct");
$sel->click_ok("categoryAction-include");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->remove_all_selections_ok("inclusion_to_remove");
$sel->add_selection_ok("inclusion_to_remove", "label=__Any__:__Any__");
$sel->click_ok("categoryAction-removeInclusion");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->select_ok("product", "label=QA-Selenium-TEST");
$sel->click_ok("categoryAction-exclude");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
$sel->select_ok("product", "label=QA-Selenium-TEST");
$sel->click_ok("categoryAction-include");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs");
my @inclusion = $sel->get_select_options("inclusion_to_remove");
ok(scalar @inclusion == 2, "The inclusion list contains 2 elements");
ok(grep($_ eq "QA-Selenium-TEST:__Any__", @inclusion), "QA-Selenium-TEST:__Any__ is in the inclusion list");
ok(grep($_ eq "TestProduct:__Any__", @inclusion), "TestProduct:__Any__ is in the inclusion list");
my @exclusion = $sel->get_select_options("exclusion_to_remove");
ok(scalar @exclusion == 1, "The exclusion list contains 1 element");
ok($exclusion[0] eq "QA-Selenium-TEST:__Any__", "QA-Selenium-TEST:__Any__ is in the exclusion list");
$sel->type_ok("sortkey", "900");
$sel->value_is("cc_list", "");
$sel->value_is("is_active", "on");
$sel->value_is("is_requestable", "on");
$sel->value_is("is_requesteeble", "on");
$sel->value_is("is_multiplicable", "on");
$sel->select_ok("grant_group", "label=admin");
$sel->select_ok("request_group", "label=(no group)");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'SeleniumBugFlag1Test' Created");
$sel->is_text_present_ok("The flag type SeleniumBugFlag1Test has been created.");
my $flagtype_url = $sel->get_attribute('link=SeleniumBugFlag1Test@href');
$flagtype_url =~ /id=(\d+)$/;
my $flagtype1_id = $1;

# Clone the flag type, but set the request group to 'editbugs' and the sortkey to 950.

$sel->click_ok("//a[\@href='editflagtypes.cgi?action=copy&id=$flagtype1_id']");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs Based on SeleniumBugFlag1Test");
$sel->type_ok("name", "SeleniumBugFlag2Test");
$sel->type_ok("description", "bugflag2");
@inclusion = $sel->get_select_options("inclusion_to_remove");
ok(scalar @inclusion == 2, "The inclusion list contains 2 elements");
ok(grep($_ eq "QA-Selenium-TEST:__Any__", @inclusion), "QA-Selenium-TEST:__Any__ is in the inclusion list");
ok(grep($_ eq "TestProduct:__Any__", @inclusion), "TestProduct:__Any__ is in the inclusion list");
@exclusion = $sel->get_select_options("exclusion_to_remove");
ok(scalar @exclusion == 1, "The exclusion list contains 1 element");
ok($exclusion[0] eq "QA-Selenium-TEST:__Any__", "QA-Selenium-TEST:__Any__ is in the exclusion list");
$sel->type_ok("sortkey", "950");
$sel->value_is("is_active", "on");
$sel->value_is("is_requestable", "on");
$sel->value_is("is_requesteeble", "on");
$sel->value_is("is_multiplicable", "on");
$sel->type_ok("cc_list", $config->{canconfirm_user_login});
$sel->selected_label_is("grant_group", "admin");
$sel->select_ok("request_group", "label=editbugs");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'SeleniumBugFlag2Test' Created");
$sel->is_text_present_ok("The flag type SeleniumBugFlag2Test has been created.");
$flagtype_url = $sel->get_attribute('link=SeleniumBugFlag2Test@href');
$flagtype_url =~ /id=(\d+)$/;
my $flagtype2_id = $1;

# Clone the first flag type again, but with different attributes.

$sel->click_ok("//a[\@href='editflagtypes.cgi?action=copy&id=$flagtype1_id']");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Bugs Based on SeleniumBugFlag1Test");
$sel->type_ok("name", "SeleniumBugFlag3Test");
$sel->type_ok("description", "bugflag3");
$sel->type_ok("sortkey", "980");
$sel->value_is("is_active", "on");
$sel->value_is("is_requestable", "on");
$sel->uncheck_ok("is_requesteeble");
$sel->uncheck_ok("is_multiplicable");
$sel->value_is("cc_list", "");
$sel->select_ok("grant_group", "label=(no group)");
$sel->selected_label_is("request_group", "(no group)");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'SeleniumBugFlag3Test' Created");
$sel->is_text_present_ok("The flag type SeleniumBugFlag3Test has been created.");
$flagtype_url = $sel->get_attribute('link=SeleniumBugFlag3Test@href');
$flagtype_url =~ /id=(\d+)$/;
my $flagtype3_id = $1;

# We now create a flag type for attachments.

$sel->click_ok("link=Create Flag Type For Attachments");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Attachments");
$sel->type_ok("name", "SeleniumAttachmentFlag1Test");
$sel->type_ok("description", "attachmentflag1");
$sel->select_ok("product", "label=TestProduct");
$sel->click_ok("categoryAction-include");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Attachments");
$sel->remove_all_selections_ok("inclusion_to_remove");
$sel->add_selection_ok("inclusion_to_remove", "label=__Any__:__Any__");
$sel->click_ok("categoryAction-removeInclusion");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Attachments");
@inclusion = $sel->get_select_options("inclusion_to_remove");
ok(scalar @inclusion == 1, "The inclusion list contains 1 element");
ok($inclusion[0] eq "TestProduct:__Any__", "TestProduct:__Any__ is in the exclusion list");
$sel->type_ok("sortkey", "700");
$sel->value_is("cc_list", "");
$sel->select_ok("grant_group", "label=editbugs");
$sel->select_ok("request_group", "label=canconfirm");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'SeleniumAttachmentFlag1Test' Created");
$sel->is_text_present_ok("The flag type SeleniumAttachmentFlag1Test has been created.");
$flagtype_url = $sel->get_attribute('link=SeleniumAttachmentFlag1Test@href');
$flagtype_url =~ /id=(\d+)$/;
my $aflagtype1_id = $1;

# Clone the flag type.

$sel->click_ok("//a[\@href='editflagtypes.cgi?action=copy&id=$aflagtype1_id']");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Attachments Based on SeleniumAttachmentFlag1Test");
$sel->type_ok("name", "SeleniumAttachmentFlag2Test");
$sel->type_ok("description", "attachmentflag2");
@inclusion = $sel->get_select_options("inclusion_to_remove");
ok(scalar @inclusion == 1, "The inclusion list contains 1 element");
ok($inclusion[0] eq "TestProduct:__Any__", "TestProduct:__Any__ is in the exclusion list");
$sel->type_ok("sortkey", "750");
$sel->type_ok("cc_list", $config->{admin_user_login});
$sel->uncheck_ok("is_multiplicable");
$sel->select_ok("grant_group", "label=(no group)");
$sel->select_ok("request_group", "label=(no group)");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'SeleniumAttachmentFlag2Test' Created");
$sel->is_text_present_ok("The flag type SeleniumAttachmentFlag2Test has been created.");
$flagtype_url = $sel->get_attribute('link=SeleniumAttachmentFlag2Test@href');
$flagtype_url =~ /id=(\d+)$/;
my $aflagtype2_id = $1;

# Clone the flag type again, and set it as inactive.

$sel->click_ok("//a[\@href='editflagtypes.cgi?action=copy&id=$aflagtype1_id']");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create Flag Type for Attachments Based on SeleniumAttachmentFlag1Test");
$sel->type_ok("name", "SeleniumAttachmentFlag3Test");
$sel->type_ok("description", "attachmentflag3");
$sel->type_ok("sortkey", "800");
$sel->uncheck_ok("is_active");
$sel->click_ok("save");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Type 'SeleniumAttachmentFlag3Test' Created");
$sel->is_text_present_ok("The flag type SeleniumAttachmentFlag3Test has been created.");
$flagtype_url = $sel->get_attribute('link=SeleniumAttachmentFlag3Test@href');
$flagtype_url =~ /id=(\d+)$/;
my $aflagtype3_id = $1;

# All flag types have been created. Now "real" tests can start.

file_bug_in_product($sel, 'TestProduct');
$sel->type_ok("short_desc", "test flags");
$sel->type_ok("comment", "this bug is used by Selenium to test flags");
# Restrict the bug to the Master group. That's important for subsequent tests!
$sel->check_ok('//input[@name="groups" and @value="Master"]');
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
my $bug1_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
$sel->is_text_present_ok('has been added to the database', "Bug $bug1_id created");

# All 3 bug flag types must be available; we are in the TestProduct product.

$sel->click_ok("link=Bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id .* test flags/);
$sel->is_text_present_ok("SeleniumBugFlag1Test");
# We specify //select or //input, just to be sure. This is not required, though.
$sel->is_element_present_ok("//select[\@id='flag_type-$flagtype1_id']");
$sel->is_element_present_ok("//input[\@id='requestee_type-$flagtype1_id']");
# If fields are of the correct type above, we assume this is still true below.
$sel->is_text_present_ok("SeleniumBugFlag2Test");
$sel->is_element_present_ok("flag_type-$flagtype2_id");
$sel->is_element_present_ok("requestee_type-$flagtype2_id");
$sel->is_text_present_ok("SeleniumBugFlag3Test");
$sel->is_element_present_ok("flag_type-$flagtype3_id");
ok(!$sel->is_element_present("requestee_type-$flagtype3_id"), "SeleniumBugFlag3Test is not specifically requestable");

# This is intentional to generate "flagmail". Some flags have a CC list
# associated with them, some others don't. This is to catch crashes due to
# the MTA.

$sel->select_ok("flag_type-$flagtype1_id", "label=?");
$sel->select_ok("flag_type-$flagtype2_id", "label=?");
$sel->select_ok("flag_type-$flagtype3_id", "label=?");
$sel->type_ok("comment", "Setting all 3 flags to ?");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);

# We need to store the new flag IDs.

$sel->is_text_present_ok("$config->{admin_user_nick}: SeleniumBugFlag1Test");
my $flag1_1_id = $sel->get_attribute('//select[@title="bugflag1"]@id');
$flag1_1_id =~ s/flag-//;
$sel->is_text_present_ok("$config->{admin_user_nick}: SeleniumBugFlag2Test");
my $flag2_1_id = $sel->get_attribute('//select[@title="bugflag2"]@id');
$flag2_1_id =~ s/flag-//;
$sel->is_text_present_ok("$config->{admin_user_nick}: SeleniumBugFlag3Test");
my $flag3_1_id = $sel->get_attribute('//select[@title="bugflag3"]@id');
$flag3_1_id =~ s/flag-//;

$sel->is_text_present_ok("addl. SeleniumBugFlag1Test");
$sel->is_text_present_ok("addl. SeleniumBugFlag2Test");
ok(!$sel->is_text_present("addl. SeleniumBugFlag3Test"), "SeleniumBugFlag3Test is not multiplicable");
$sel->select_ok("flag_type-$flagtype1_id", "label=+");
$sel->select_ok("flag_type-$flagtype2_id", "label=-");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);

# Now let's test requestees. SeleniumBugFlag2Test requires the requestee
# to be in the editbugs group.

$sel->select_ok("flag_type-$flagtype1_id", "label=?");
$sel->type_ok("requestee_type-$flagtype1_id", $config->{admin_user_login});
$sel->select_ok("flag_type-$flagtype2_id", "label=?");
$sel->type_ok("requestee_type-$flagtype2_id", $config->{unprivileged_user_login});
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Flag Requestee Not Authorized");
$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->type_ok("requestee_type-$flagtype2_id", $config->{admin_user_login});
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);

# Final tests for bug flags.

$sel->select_ok("flag-$flag1_1_id", "value=X");
$sel->select_ok("flag-$flag2_1_id", "label=+");
$sel->select_ok("flag-$flag3_1_id", "label=-");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);

# Now we test attachment flags.

$sel->click_ok("link=Add an attachment");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create New Attachment for Bug #$bug1_id");
$sel->type_ok("data", $config->{attachment_file});
$sel->type_ok("description", "patch, v1");
$sel->check_ok("ispatch");
$sel->is_text_present_ok("SeleniumAttachmentFlag1Test");
$sel->is_text_present_ok("SeleniumAttachmentFlag2Test");
ok(!$sel->is_text_present("SeleniumAttachmentFlag3Test"), "Inactive SeleniumAttachmentFlag3Test flag type not displayed");

# Let's generate some "flagmail", first with no requestee.

$sel->select_ok("flag_type-$aflagtype1_id", "label=?");
$sel->select_ok("flag_type-$aflagtype2_id", "label=?");
$sel->type_ok("comment", "patch for testing purposes only");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('regexp:Attachment #\d+ to bug \d+ created');

# Store the flag ID.

my $alink = $sel->get_attribute('//a[@title="patch, v1"]@href');
$alink =~ /id=(\d+)/;
my $attachment1_id = $1;

# Now create another attachment, and set requestees.

$sel->click_ok("//a[contains(text(),'Create\n Another Attachment to Bug $bug1_id')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create New Attachment for Bug #$bug1_id");
$sel->type_ok("data", $config->{attachment_file});
$sel->type_ok("description", "patch, v2");
$sel->check_ok("ispatch");
# Mark the previous attachment as obsolete.
$sel->check_ok($attachment1_id);
$sel->select_ok("flag_type-$aflagtype1_id", "label=?");
$sel->type_ok("requestee_type-$aflagtype1_id", $config->{admin_user_login});
$sel->select_ok("flag_type-$aflagtype2_id", "label=?");
# The requestee is not in the Master group, and so he cannot view the bug.
# He must be silently skipped from the requestee field.
$sel->type_ok("requestee_type-$aflagtype2_id", $config->{unprivileged_user_login});
$sel->type_ok("comment", "second patch, with requestee");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('regexp:Attachment #\d+ to bug \d+ created');
$alink = $sel->get_attribute('//a[@title="patch, v2"]@href');
$alink =~ /id=(\d+)/;
my $attachment2_id = $1;

# Create a third attachment, but we now set the MIME type manually.

$sel->click_ok("//a[contains(text(),'Create\n Another Attachment to Bug $bug1_id')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create New Attachment for Bug #$bug1_id");
$sel->type_ok("data", $config->{attachment_file});
$sel->type_ok("description", "patch, v3");
$sel->click_ok("list");
$sel->select_ok("contenttypeselection", "label=plain text (text/plain)");
$sel->select_ok("flag_type-$aflagtype1_id", "label=+");
$sel->type_ok("comment", "one +, the other one blank");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('regexp:Attachment #\d+ to bug \d+ created');
$alink = $sel->get_attribute('//a[@title="patch, v3"]@href');
$alink =~ /id=(\d+)/;
my $attachment3_id = $1;

# Display the bug and check flags are correctly set.

$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);
$sel->is_text_present_ok("$config->{admin_user_nick}: SeleniumAttachmentFlag1Test? ($config->{admin_user_nick})");
$sel->is_text_present_ok("$config->{admin_user_nick}: SeleniumAttachmentFlag2Test?");
$sel->is_text_present_ok("$config->{admin_user_nick}: SeleniumAttachmentFlag1Test+");
# We marked the first attachment as obsolete, so it should have no flag on it.
$sel->is_text_present_ok("no flags");

# Make the bug public and log out.

$sel->uncheck_ok('//input[@name="groups" and @value="Master"]');
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
logout($sel);

# As an unprivileged user, try to edit flags.

log_in($sel, $config, 'unprivileged');
go_to_bug($sel, $bug1_id);
# No privs are required to clear this flag.
$sel->select_ok("flag-$flag3_1_id", "value=X");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug1_id");
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);

# editbugs privs are required to clear this flag, so no other option
# should be displayed besides the currently set "+".

my @flag_states = $sel->get_select_options("flag-$flag2_1_id");
ok(scalar(@flag_states) == 1 && $flag_states[0] eq '+', "Single flag state '+' available");

# Powerless users cannot set the flag to +, but setting it to ? is allowed.

@flag_states = $sel->get_select_options("flag_type-$flagtype1_id");
ok(scalar @flag_states == 2, "Two flag states available");
ok(grep($_ eq '?', @flag_states), "Flag state '?' available");

# A powerless user cannot edit someone else's attachment flags.

$sel->click_ok("//a[\@href='attachment.cgi?id=$attachment2_id&action=edit']");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^Attachment $attachment2_id Details for Bug $bug1_id/);
$sel->is_element_present_ok('//select[@title="attachmentflag2"][@disabled]',
   "Attachment flags are not editable by a powerless user");

# Add an attachment and set flags on it.

$sel->click_ok("link=Bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id/);
$sel->click_ok("link=Add an attachment");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create New Attachment for Bug #$bug1_id");
$sel->type_ok("data", $config->{attachment_file});
$sel->type_ok("description", "patch, v4");
$sel->value_is("ispatch", "on");

# canconfirm/editbugs privs are required to edit this flag.

ok(!$sel->is_editable("flag_type-$aflagtype1_id"), "Flag type non editable by powerless users");

# No privs are required to edit this flag.

$sel->select_ok("flag_type-$aflagtype2_id", "label=+");
$sel->type_ok("comment", "granting again");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('regexp:Attachment #\d+ to bug \d+ created');
$sel->click_ok("link=bug $bug1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id/);
$sel->is_text_present_ok("$config->{unprivileged_user_nick}: SeleniumAttachmentFlag2Test+");
logout($sel);

# Final tests as an admin. He has editbugs privs, so he can edit
# someone else's patch.

log_in($sel, $config, 'admin');
go_to_bug($sel, $bug1_id);
$sel->click_ok("//a[\@href='attachment.cgi?id=${attachment3_id}&action=edit']");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^Attachment $attachment3_id Details for Bug $bug1_id/);
$sel->select_ok('//select[@title="attachmentflag1"]', "label=+");
$sel->click_ok("update");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes to attachment $attachment3_id of bug $bug1_id submitted");

# It's time to delete all created flag types.

go_to_admin($sel);
$sel->click_ok("link=Flags");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Administer Flag Types");

foreach my $flagtype ([$flagtype1_id, "SeleniumBugFlag1Test"], [$flagtype2_id, "SeleniumBugFlag2Test"],
                      [$flagtype3_id, "SeleniumBugFlag3Test"], [$aflagtype1_id, "SeleniumAttachmentFlag1Test"],
                      [$aflagtype2_id, "SeleniumAttachmentFlag2Test"], [$aflagtype3_id, "SeleniumAttachmentFlag3Test"])
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
