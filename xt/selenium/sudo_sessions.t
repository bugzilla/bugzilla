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

# Turn on the usevisibilitygroups param so that some users are invisible.

log_in($sel, $config, 'admin');
set_parameters($sel, { "Group Security" => {"usevisibilitygroups-on" => undef} });

# You can see all users from editusers.cgi, but once you leave this page,
# usual group visibility restrictions apply and the "powerless" user cannot
# be sudo'ed as he is in no group.

go_to_admin($sel);
$sel->click_ok("link=Users");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search users");
$sel->type_ok("matchstr", $config->{unprivileged_user_login});
$sel->select_ok("matchtype", "label=exact (find this user)");
$sel->click_ok("search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit user no-privs <$config->{unprivileged_user_login}>");
$sel->value_is("login", $config->{unprivileged_user_login});
$sel->click_ok("link=Impersonate this user");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Begin sudo session");
$sel->value_is("target_login", $config->{unprivileged_user_login});
$sel->type_ok("reason", "Selenium test about sudo sessions");
$sel->type_ok("password", $config->{admin_user_passwd}, "Enter admin password");
$sel->click_ok('//input[@value="Begin Session"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Match Failed");
my $error_msg = trim($sel->get_text("error_msg"));
ok($error_msg eq "$config->{unprivileged_user_login} does not exist or you are not allowed to see that user.",
   "Cannot impersonate users you cannot see");

# Turn off the usevisibilitygroups param so that all users are visible again.

set_parameters($sel, { "Group Security" => {"usevisibilitygroups-off" => undef} });

# The "powerless" user can now be sudo'ed.

go_to_admin($sel);
$sel->click_ok("link=Users");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search users");
$sel->type_ok("matchstr", $config->{unprivileged_user_login});
$sel->select_ok("matchtype", "label=exact (find this user)");
$sel->click_ok("search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit user no-privs <$config->{unprivileged_user_login}>");
$sel->value_is("login", $config->{unprivileged_user_login});
$sel->click_ok("link=Impersonate this user");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Begin sudo session");
$sel->value_is("target_login", $config->{unprivileged_user_login});
$sel->type_ok("password", $config->{admin_user_passwd}, "Enter admin password");
$sel->click_ok('//input[@value="Begin Session"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Sudo session started");
my $text = trim($sel->get_text("message"));
ok($text =~ /The sudo session has been started/, "The sudo session has been started");

# Make sure this user is not an admin and has no privs at all, and that
# he cannot access editusers.cgi (despite the sudoer can).

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("General Preferences");
$sel->click_ok("link=Permissions");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Permissions");
$sel->is_text_present_ok("There are no permission bits set on your account");
# We access the page directly as there is no link pointing to it.
$sel->open_ok("/$config->{bugzilla_installation}/editusers.cgi");
$sel->title_is("Authorization Required");
$error_msg = trim($sel->get_text("error_msg"));
ok($error_msg =~ /^Sorry, you aren't a member of the 'editusers' group/, "Not a member of the editusers group");
$sel->click_ok("link=end session");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Sudo session complete");
$sel->is_text_present_ok("Your sudo session has ended");

# Try to access the sudo page directly, with no credentials.

$sel->open_ok("/$config->{bugzilla_installation}/relogin.cgi?action=begin-sudo&target_login=$config->{admin_user_login}");
$sel->title_is("Password Required");

# Now try to start a sudo session directly, with all required credentials.

$sel->open_ok("/$config->{bugzilla_installation}/relogin.cgi?action=begin-sudo&password=$config->{admin_user_passwd}&target_login=$config->{unprivileged_user_login}", undef, "Impersonate a user directly by providing all required data");
# A direct access to the page is supposed to have no Referer header set,
# which would trigger the "Untrusted Authentication Request" error, but
# due to the way Selenium works, the Referer header is set and the
# "Preparation Required" error is thrown instead. In any case, one of
# those two errors must be thrown.
my $title = $sel->get_title();
ok($title eq "Untrusted Authentication Request" || $title eq "Preparation Required", $title);

# Now try to sudo an admin, which is not allowed.

$sel->open_ok("/$config->{bugzilla_installation}/relogin.cgi?action=prepare-sudo&target_login=$config->{admin_user_login}");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Begin sudo session");
$sel->value_is("target_login", $config->{admin_user_login});
$sel->type_ok("reason", "Selenium hack");
$sel->type_ok("password", $config->{admin_user_passwd}, "Enter admin password");
$sel->click_ok('//input[@value="Begin Session"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Protected");
$error_msg = trim($sel->get_text("error_msg"));
ok($error_msg =~ /^The user $config->{admin_user_login} may not be impersonated by sudoers/, "Cannot impersonate administrators");

# Now try to sudo a non-existing user account, with no password.

$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Begin sudo session");
# Starting with 5.0, the password field is a type=password and is marked
# "required". This means that we need to remove the required attribute from
# the input so that it can still be checked by the backend code.
my $script = q{
    document.getElementById('password').removeAttribute('required');
};
$sel->run_script($script);
$sel->type_ok("target_login", 'foo@bar.com');
$sel->click_ok('//input[@value="Begin Session"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Password Required");

# Same as above, but with your password.

$sel->open_ok("/$config->{bugzilla_installation}/relogin.cgi?action=prepare-sudo&target_login=foo\@bar.com");
$sel->title_is("Begin sudo session");
$sel->value_is("target_login", 'foo@bar.com');
$sel->type_ok("password", $config->{admin_user_passwd}, "Enter admin password");
$sel->click_ok('//input[@value="Begin Session"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Match Failed");
$error_msg = trim($sel->get_text("error_msg"));
ok($error_msg eq 'foo@bar.com does not exist or you are not allowed to see that user.', "Cannot impersonate non-existing accounts");
logout($sel);
