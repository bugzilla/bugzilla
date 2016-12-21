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
set_parameters($sel, { "Administrative Policies" => {"allowuserdeletion-on" => undef} });

# First delete test users, if not deleted correctly during a previous run.

cleanup_users($sel);

# The Master group inherits privs of the Slave group.

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

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok("link=Add Group");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add group");
$sel->type_ok("name", "Slave");
$sel->type_ok("desc", "Members of the Master group are also members of this group");
$sel->type_ok("owner", $config->{'admin_user_login'});
$sel->uncheck_ok("isactive");
ok(!$sel->is_checked("insertnew"), "Group not added to products by default");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("New Group Created");
my $slave_gid = $sel->get_value("group_id");
$sel->add_selection_ok("members_add", "label=Master");
$sel->click_ok('//input[@value="Update Group"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Group: Slave");

# Create users.

go_to_admin($sel);
$sel->click_ok("link=Users");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Search users');
$sel->click_ok('link=add a new user');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Add user');
$sel->type_ok('login', 'master@selenium.bugzilla.org');
$sel->type_ok('name', 'master-user');
$sel->type_ok('password', 'selenium', 'Enter password');
$sel->type_ok('disabledtext', 'Not for common usage');
$sel->click_ok('add');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Edit user master-user <master@selenium.bugzilla.org>');
$sel->check_ok("//input[\@name='group_$master_gid']");
$sel->click_ok('update');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('User master@selenium.bugzilla.org updated');
$sel->is_text_present_ok('The account has been added to the Master group');

$sel->click_ok("//a[contains(text(),'add\n    a new user')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Add user');
$sel->type_ok('login', 'slave@selenium.bugzilla.org');
$sel->type_ok('name', 'slave-user');
$sel->type_ok('password', 'selenium', 'Enter password');
$sel->type_ok('disabledtext', 'Not for common usage');
$sel->click_ok('add');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Edit user slave-user <slave@selenium.bugzilla.org>');
$sel->check_ok("//input[\@name='group_$slave_gid']");
$sel->click_ok('update');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('User slave@selenium.bugzilla.org updated');
$sel->is_text_present_ok('The account has been added to the Slave group');

$sel->click_ok("//a[contains(text(),'add\n    a new user')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Add user');
$sel->type_ok('login', 'reg@selenium.bugzilla.org');
$sel->type_ok('name', 'reg-user');
$sel->type_ok('password', 'selenium', 'Enter password');
$sel->type_ok('disabledtext', 'Not for common usage');
$sel->click_ok('add');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Edit user reg-user <reg@selenium.bugzilla.org>');

# Now make sure group inheritance works correctly.

$sel->click_ok('link=find other users');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Search users');
$sel->check_ok('grouprestrict');
$sel->select_ok('groupid', 'label=Master');
$sel->select_ok('matchtype', 'value=substr');
$sel->click_ok('search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('master@selenium.bugzilla.org', 'master-user in Master group');
ok(!$sel->is_text_present('slave@selenium.bugzilla.org'), 'slave-user not in Master group');
ok(!$sel->is_text_present('reg@selenium.bugzilla.org'), 'reg-user not in Master group');

$sel->click_ok('link=find other users');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Search users');
$sel->check_ok('grouprestrict');
$sel->select_ok('groupid', 'label=Slave');
$sel->select_ok('matchtype', 'value=substr');
$sel->click_ok('search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('master@selenium.bugzilla.org', 'master-user in Slave group');
$sel->is_text_present_ok('slave@selenium.bugzilla.org', 'slave-user in Slave group');
ok(!$sel->is_text_present('reg@selenium.bugzilla.org'), 'reg-user not in Slave group');

# Add a regular expression to the Slave group.

go_to_admin($sel);
$sel->click_ok("link=Groups");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Groups");
$sel->click_ok('link=Slave');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Change Group: Slave');
$sel->type_ok('regexp', '^reg\@.*$');
$sel->click_ok('//input[@value="Update Group"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Group: Slave");

# Test group inheritance again.

go_to_admin($sel);
$sel->click_ok("link=Users");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Search users');
$sel->check_ok('grouprestrict');
$sel->select_ok('groupid', 'label=Master');
$sel->select_ok('matchtype', 'value=substr');
$sel->click_ok('search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('master@selenium.bugzilla.org', 'master-user in Master group');
ok(!$sel->is_text_present('slave@selenium.bugzilla.org'), 'slave-user not in Master group');
ok(!$sel->is_text_present('reg@selenium.bugzilla.org'), 'reg-user not in Master group');

$sel->click_ok('link=find other users');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Search users');
$sel->check_ok('grouprestrict');
$sel->select_ok('groupid', 'label=Slave');
$sel->select_ok('matchtype', 'value=substr');
$sel->click_ok('search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('master@selenium.bugzilla.org', 'master-user in Slave group');
$sel->is_text_present_ok('slave@selenium.bugzilla.org', 'slave-user in Slave group');
$sel->is_text_present_ok('reg@selenium.bugzilla.org', 'reg-user in Slave group');

# Remove created users and groups.

cleanup_users($sel);
cleanup_groups($sel, $slave_gid);
logout($sel);

sub cleanup_users {
    my $sel = shift;

    go_to_admin($sel);
    $sel->click_ok("link=Users");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Search users");
    $sel->type_ok('matchstr', '(master|slave|reg)@selenium.bugzilla.org');
    $sel->select_ok('matchtype', 'value=regexp');
    $sel->click_ok("search");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Select user");

    foreach my $user ('master', 'slave', 'reg') {
        my $login = $user . '@selenium.bugzilla.org';
        next unless $sel->is_text_present($login);

        $sel->click_ok("link=$login");
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
        $sel->title_is("Edit user ${user}-user <$login>");
        $sel->click_ok("delete");
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
        $sel->title_is("Confirm deletion of user $login");
        ok(!$sel->is_text_present('You cannot delete this user account'), 'The user can be safely deleted');
        $sel->click_ok("delete");
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
        $sel->title_is("User $login deleted");
        $sel->click_ok('link=show the user list again');
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
        $sel->title_is('Select user');
    }
}

sub cleanup_groups {
    my ($sel, $slave_gid) = @_;

    go_to_admin($sel);
    $sel->click_ok("link=Groups");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Edit Groups");
    $sel->click_ok("//a[\@href='editgroups.cgi?action=del&group=$slave_gid']");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Delete group");
    $sel->is_text_present_ok("Do you really want to delete this group?");
    ok(!$sel->is_element_present("removeusers"), 'No direct members in this group');
    $sel->click_ok("delete");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Group Deleted");
    $sel->is_text_present_ok("The group Slave has been deleted.");
}
