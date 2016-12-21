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
my $test_bug_1 = $config->{test_bug_1};

# When being logged out, the 'Commit' button should not be displayed.

$sel->open_ok("/$config->{bugzilla_installation}/index.cgi?logout=1", undef, "Log out (if required)");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Logged Out");
go_to_bug($sel, $test_bug_1);
ok(!$sel->is_element_present('commit'), "Button 'Commit' not available");

# Now create a new bug. As the reporter, some forms are editable to you.
# But as you don't have editbugs privs, you cannot edit everything.

log_in($sel, $config, 'unprivileged');
file_bug_in_product($sel, 'TestProduct');
ok(!$sel->is_editable("assigned_to"), "The assignee field is not editable");
$sel->type_ok("short_desc", "Greetings from a powerless user");
$sel->type_ok("comment", "File a bug with an empty CC list");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
my $bug1_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");
$sel->is_text_present_ok('has been added to the database', "Bug $bug1_id created");
logout($sel);

# Some checks while being logged out.

go_to_bug($sel, $bug1_id);
ok(!$sel->is_element_present("commit"), "Button 'Commit' not available");
my $text = trim($sel->get_text("//fieldset"));
ok($text =~ /You need to log in before you can comment on or make changes to this bug./,
   "Addl. comment box not displayed");

# Don't call log_in() here. We explicitly want to use the "log in" link
# in the addl. comment box.

$sel->click_ok("link=log in");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Log in to Bugzilla");
$sel->is_text_present_ok("I need an email address and password to continue.");
$sel->type_ok("Bugzilla_login", $config->{unprivileged_user_login}, "Enter login name");
$sel->type_ok("Bugzilla_password", $config->{unprivileged_user_passwd}, "Enter password");
$sel->click_ok("log_in", undef, "Submit credentials");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id/, "Display bug $bug1_id");

# Neither the (edit) link nor the hidden form must exist, at all.
# But the 'Commit' button does exist.

ok(!$sel->is_element_present("bz_assignee_edit_action"), "No (edit) link displayed for the assignee");
ok(!$sel->is_element_present("assigned_to"), "No hidden assignee field available");
$sel->is_element_present_ok("commit");
logout($sel);
