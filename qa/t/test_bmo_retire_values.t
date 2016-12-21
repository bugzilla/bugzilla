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
my ($text, $bug_id);

my $admin_user_login = $config->{admin_user_login};

log_in($sel, $config, 'admin');
set_parameters($sel, { "Bug Fields"              => {"useclassification-off" => undef,
                                                     "usetargetmilestone-on" => undef},
                       "Administrative Policies" => {"allowbugdeletion-on"   => undef},
                     });

# create a clean bug

file_bug_in_product($sel, "TestProduct");
$sel->select_ok("component", "label=TestComponent");
$sel->type_ok("short_desc", "testing testComponent");
$sel->type_ok("comment", "testing");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
my $clean_bug_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");
$sel->is_text_present_ok('has been added to the database', "Bug $clean_bug_id created");

#
# component
#
# add a new component to TestProduct

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok("link=TestProduct");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'TestProduct'");
$sel->click_ok("link=Edit components:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select component of product 'TestProduct'");
$text = trim($sel->get_text("bugzilla-body"));
if ($text =~ /TempComponent/) {
    $sel->click_ok("//a[contains(\@href, 'editcomponents.cgi?action=del&product=TestProduct&component=TempComponent')]");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Delete component 'TempComponent' from 'TestProduct' product");
    $sel->click_ok("delete");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Component Deleted");
}
$sel->click_ok("link=Add");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add component to the TestProduct product");
$sel->type_ok("component", "TempComponent");
$sel->type_ok("description", "Temp component");
$sel->type_ok("initialowner", $admin_user_login);
$sel->uncheck_ok("watch_user_auto");
$sel->type_ok("watch_user", 'tempcomponent@testproduct.bugs');
$sel->check_ok("watch_user_auto");
$sel->click_ok('//input[@type="submit" and @value="Add"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Component Created");

# create bug into TempComponent

file_bug_in_product($sel, "TestProduct");
$sel->select_ok("component", "label=TempComponent");
$sel->type_ok("short_desc", "testing tempComponent");
$sel->type_ok("comment", "testing");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$bug_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");
$sel->is_text_present_ok('has been added to the database', "Bug $bug_id created");

# disable TestProduct:TestComponent for bug entry

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok("link=TestProduct");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'TestProduct'");
$sel->click_ok("link=Edit components:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select component of product 'TestProduct'");
$sel->click_ok("link=TempComponent");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit component 'TempComponent' of product 'TestProduct'");
$sel->click_ok("isactive");
$sel->click_ok("update");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Component Updated");
$text = trim($sel->get_text("bugzilla-body"));
ok($text =~ /Disabled for bugs/, "Component deactivation confirmed");

# update bug TempComponent bug

go_to_bug($sel, $bug_id);
# make sure the component is still tempcomponent
$sel->selected_label_is("component", 'TempComponent');
# update
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
$sel->click_ok("link=bug $bug_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
# make sure the component is still tempcomponent
ok($sel->get_selected_labels("component"), 'TempComponent');

# try creating new bug with TempComponent

file_bug_in_product($sel, "TestProduct");
ok(!$sel->is_element_present(
    q#//select[@id='component']/option[@value='TempComponent']#),
    'TempComponent is missing from create');

# try changing compoent of existing bug to TempComponent

go_to_bug($sel, $clean_bug_id);
ok(!$sel->is_element_present(
    q#//select[@id='component']/option[@value='TempComponent']#),
    'TempComponent is missing from update');

# delete TempComponent

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok("link=TestProduct");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'TestProduct'");
$sel->click_ok("link=Edit components:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->click_ok("//a[contains(\@href, 'editcomponents.cgi?action=del&product=TestProduct&component=TempComponent')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete component 'TempComponent' from 'TestProduct' product");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Component Deleted");

#
# version
#

# add a new version to TestProduct

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok("link=TestProduct");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'TestProduct'");
$sel->click_ok("link=Edit versions:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select version of product 'TestProduct'");
$text = trim($sel->get_text("bugzilla-body"));
if ($text =~ /TempVersion/) {
    $sel->click_ok("//a[contains(\@href, 'editversions.cgi?action=del&product=TestProduct&version=TempVersion')]");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Delete Version of Product 'TestProduct'");
    $sel->click_ok("delete");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Version Deleted");
}
$sel->click_ok("link=Add");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add Version to Product 'TestProduct'");
$sel->type_ok("version", "TempVersion");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Version Created");

# create bug with new version

file_bug_in_product($sel, "TestProduct");
$sel->select_ok("version", "label=TempVersion");
$sel->type_ok("short_desc", "testing tempVersion");
$sel->type_ok("comment", "testing");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$bug_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");
$sel->is_text_present_ok('has been added to the database', "Bug $bug_id created");

# disable new version for bug entry

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok("link=TestProduct");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'TestProduct'");
$sel->click_ok("link=Edit versions:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select version of product 'TestProduct'");
$sel->click_ok("link=TempVersion");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Version 'TempVersion' of product 'TestProduct'");
$sel->click_ok("isactive");
$sel->click_ok("update");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Version Updated");
$text = trim($sel->get_text("bugzilla-body"));
ok($text =~ /Disabled for bugs/, "Version deactivation confirmed");

# update new version bug

go_to_bug($sel, $bug_id);
# make sure the version is still tempversion
$sel->selected_label_is("version", 'TempVersion');
# update
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
$sel->click_ok("link=bug $bug_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
# make sure the version is still tempversion
$sel->selected_label_is("version", 'TempVersion');
# change the version so it can be deleted
$sel->select_ok("version", "label=unspecified");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug_id");

# try creating new bug with new version

file_bug_in_product($sel, "TestProduct");
ok(!$sel->is_element_present(
    q#//select[@id='version']/option[@value='TempVersion']#),
    'TempVersion is missing from create');

# try changing existing bug to new version

go_to_bug($sel, $clean_bug_id);
ok(!$sel->is_element_present(
    q#//select[@id='version']/option[@value='TempVersion']#),
    'TempVersion is missing from update');

# delete new version

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok("link=TestProduct");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'TestProduct'");
$sel->click_ok("link=Edit versions:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select version of product 'TestProduct'");
$text = trim($sel->get_text("bugzilla-body"));
$sel->click_ok("//a[contains(\@href, 'editversions.cgi?action=del&product=TestProduct&version=TempVersion')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Version of Product 'TestProduct'");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Version Deleted");

#
# milestone
#

# add a milestone to TestProduct

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok("link=TestProduct");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'TestProduct'");
$sel->click_ok("link=Edit milestones:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select milestone of product 'TestProduct'");
$text = trim($sel->get_text("bugzilla-body"));
if ($text =~ /TempMilestone/) {
    $sel->click_ok("//a[contains(\@href, 'editmilestones.cgi?action=del&product=TestProduct&milestone=TempMilestone')]");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Delete Milestone of Product 'TestProduct'");
    $sel->click_ok("delete");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Milestone Deleted");
}
$sel->click_ok("link=Add");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add Milestone to Product 'TestProduct'");
$sel->type_ok("milestone", "TempMilestone");
$sel->type_ok("sortkey", "999");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Milestone Created");

# create bug with milestone

file_bug_in_product($sel, "TestProduct");
$sel->select_ok("target_milestone", "label=TempMilestone");
$sel->type_ok("short_desc", "testing tempMilestone");
$sel->type_ok("comment", "testing");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$bug_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");
$sel->is_text_present_ok('has been added to the database', "Bug $bug_id created");

# disable milestone for bug entry

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok("link=TestProduct");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'TestProduct'");
$sel->click_ok("link=Edit milestones:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select milestone of product 'TestProduct'");
$sel->click_ok("link=TempMilestone");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Milestone 'TempMilestone' of product 'TestProduct'");
$sel->click_ok("isactive");
$sel->click_ok("update");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Milestone Updated");
$text = trim($sel->get_text("bugzilla-body"));
ok($text =~ /Disabled for bugs/, "Milestone deactivation confirmed");

# update milestone bug

go_to_bug($sel, $bug_id);
# make sure the milestone is still tempmilestone
$sel->selected_label_is("target_milestone", 'TempMilestone');
# update
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
$sel->click_ok("link=bug $bug_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
# make sure the milestone is still tempmilestone
$sel->selected_label_is("target_milestone", 'TempMilestone');

# try creating new bug with milestone

file_bug_in_product($sel, "TestProduct");
ok(!$sel->is_element_present(
    q#//select[@id='target_milestone']/option[@value='TempMilestone']#),
    'TempMilestone is missing from create');

# try changing existing bug to milestone

go_to_bug($sel, $clean_bug_id);
ok(!$sel->is_element_present(
    q#//select[@id='target_milestone']/option[@value='TempMilestone']#),
    'TempMilestone is missing from update');

# delete milestone

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok("link=TestProduct");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'TestProduct'");
$sel->click_ok("link=Edit milestones:");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select milestone of product 'TestProduct'");
$text = trim($sel->get_text("bugzilla-body"));
$sel->click_ok("//a[contains(\@href, 'editmilestones.cgi?action=del&product=TestProduct&milestone=TempMilestone')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Milestone of Product 'TestProduct'");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Milestone Deleted");

logout($sel);
