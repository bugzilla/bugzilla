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

# Set the email regexp for new bugzilla accounts to end with @bugzilla.test.

log_in($sel, $config, 'admin');
set_parameters($sel, { "User Authentication" => {"createemailregexp" => {type => "text", value => '[^@]+@bugzilla\.test$'}} });
logout($sel);

# Create a valid account. We need to randomize the login address, because a request
# expires after 3 days only and this test can be executed several times per day.
my $valid_account = 'selenium-' . random_string(10) . '@bugzilla.test';

$sel->is_text_present_ok("Open a New Account");
$sel->click_ok("link=Open a New Account");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create a new Bugzilla account");
$sel->type_ok("login", $valid_account);
$sel->check_ok("etiquette", "Agree to abide by code of conduct");
$sel->click_ok('//input[@value="Create Account"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Request for new user account '$valid_account' submitted");
$sel->is_text_present_ok("A confirmation email has been sent");

# Try creating the same account again. It's too soon.
$sel->click_ok("link=Home");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bugzilla Main Page");
$sel->is_text_present_ok("Open a New Account");
$sel->click_ok("link=Open a New Account");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create a new Bugzilla account");
$sel->type_ok("login", $valid_account);
$sel->check_ok("etiquette", "Agree to abide by code of conduct");
$sel->click_ok('//input[@value="Create Account"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Too Soon For New Token");
my $error_msg = trim($sel->get_text("error_msg"));
ok($error_msg =~ /Please wait a while and try again/, "Too soon for this account");

# These accounts do not pass the regexp.
my @accounts = ('test@yahoo.com', 'test@bugzilla.net', 'test@bugzilla.test.com');
foreach my $account (@accounts) {
    $sel->click_ok("link=New Account");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Create a new Bugzilla account");
    $sel->type_ok("login", $account);
    $sel->check_ok("etiquette", "Agree to abide by code of conduct");
    $sel->click_ok('//input[@value="Create Account"]');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Account Creation Restricted");
    $sel->is_text_present_ok("User account creation has been restricted.");
}

# These accounts are illegal and should cause a javascript alert.
@accounts = qw(
    test\bugzilla@bugzilla.test
    testbugzilla.test
    test@bugzilla
    test@bugzilla.
    'test'@bugzilla.test
    test&test@bugzilla.test
    [test]@bugzilla.test
);
foreach my $account (@accounts) {
    $sel->click_ok("link=New Account");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Create a new Bugzilla account");
    $sel->type_ok("login", $account);
    $sel->check_ok("etiquette", "Agree to abide by code of conduct");
    $sel->click_ok('//input[@value="Create Account"]');
    ok($sel->get_alert() =~ /The e-mail address doesn't pass our syntax checking for a legal email address/,
        'Invalid email address detected');
}

# These accounts are illegal but do not cause a javascript alert
@accounts = ('test@bugzilla.org@bugzilla.test', 'test@bugzilla..test');
# Logins larger than 127 characters must be rejected, for security reasons.
push @accounts, 'selenium-' . random_string(110) . '@bugzilla.test';
foreach my $account (@accounts) {
    $sel->click_ok("link=New Account");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Create a new Bugzilla account");
    $sel->type_ok("login", $account);
    $sel->check_ok("etiquette", "Agree to abide by code of conduct");
    $sel->click_ok('//input[@value="Create Account"]');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Invalid Email Address");
    my $error_msg = trim($sel->get_text("error_msg"));
    ok($error_msg =~ /^The e-mail address you entered (\S+) didn't pass our syntax checking/, "Invalid email address detected");
}

# This account already exists.
$sel->click_ok("link=New Account");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create a new Bugzilla account");
$sel->type_ok("login", $config->{admin_user_login});
$sel->check_ok("etiquette", "Agree to abide by code of conduct");
$sel->click_ok('//input[@value="Create Account"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Account Already Exists");
$error_msg = trim($sel->get_text("error_msg"));
ok($error_msg eq "There is already an account with the login name $config->{admin_user_login}.", "Account already exists");

# Turn off user account creation.
log_in($sel, $config, 'admin');
set_parameters($sel, { "User Authentication" => {"createemailregexp" => {type => "text", value => ''}} });
logout($sel);

# Make sure that links pointing to createaccount.cgi are all deactivated.
ok(!$sel->is_text_present("New Account"), "No link named 'New Account'");
$sel->click_ok("link=Home");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->refresh;
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bugzilla Main Page");
ok(!$sel->is_text_present("Open a New Account"), "No link named 'Open a New Account'");
$sel->open_ok("/$config->{bugzilla_installation}/createaccount.cgi");
$sel->title_is("Account Creation Disabled");
$error_msg = trim($sel->get_text("error_msg"));
ok($error_msg =~ /^User account creation has been disabled. New accounts must be created by an administrator/,
   "User account creation disabled");

# Re-enable user account creation.

log_in($sel, $config, 'admin');
set_parameters($sel, { "User Authentication" => {"createemailregexp" => {type => "text", value => '.*'}} });

# Make sure selenium-<random_string>@bugzilla.test has not be added to the DB yet.
go_to_admin($sel);
$sel->click_ok("link=Users");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search users");
$sel->type_ok("matchstr", $valid_account);
$sel->click_ok("search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select user");
$sel->is_text_present_ok("0 users found");
logout($sel);
