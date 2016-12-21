# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More "no_plan";
use QA::Util;

my ($sel, $config) = get_selenium();
log_in($sel, $config, 'admin');

set_parameters($sel, {"Administrative Policies" => {"allowuserdeletion-on" => undef},
                      "User Authentication"     => {"createemailregexp" => {type => "text", value => '.*'},
                                                    "emailsuffix" => {type => "text", value => ''}} });

# Set the password complexity to BMO.
# Password must contain at least one UPPER and one lowercase letter.
my @invalid_bmo = qw(lowercase UPPERCASE 1234567890 123lowercase 123UPPERCASE !@%&^lower !@&^UPPER);

check_passwords($sel, 'bmo', \@invalid_bmo, ['Longerthan12chars', '%9rT#j22S']);

# Set the password complexity to No Constraints.
check_passwords($sel, 'no_constraints', ['12xY!', 'aaaaa'], ['aaaaaaaa', '>F12Xy?#']);

logout($sel);

sub check_passwords {
    my ($sel, $param, $invalid_passwords, $valid_passwords) = @_;

    set_parameters($sel, { "User Authentication" => {"password_complexity" => {type => "select", value => $param}} });
    my $new_user = 'selenium-' . random_string(10) . '@bugzilla.org';

    go_to_admin($sel);
    $sel->click_ok("link=Users");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is('Search users');
    $sel->click_ok('link=add a new user');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is('Add user');
    $sel->type_ok('login', $new_user);

    foreach my $password (@$invalid_passwords) {
        $sel->type_ok('password', $password, 'Enter password');
        $sel->click_ok('add');
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
        if ($param eq 'no_constraints') {
            $sel->title_is('Password Too Short');
        }
        else {
            $sel->title_is('Password Fails Requirements');
        }

        my $error_msg = trim($sel->get_text("error_msg"));
        if ($param eq 'bmo') {
            ok($error_msg =~ /must meet three of the following requirements/,
               "Password fails requirement: $password");
        }
        else {
            ok($error_msg =~ /The password must be at least \d+ characters long/,
               "Password Too Short: $password");
        }
        $sel->go_back_ok();
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
    }

    my $created = 0;

    foreach my $password (@$valid_passwords) {
        $sel->type_ok('password', $password, 'Enter password');
        $sel->click_ok($created ? 'update' : 'add');
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
        $sel->title_is($created ? "User $new_user updated" : "Edit user $new_user");
        my $msg = trim($sel->get_text('message'));
        if ($created++) {
            ok($msg =~ /A new password has been set/, 'Account updated');
        }
        else {
            ok($msg =~ /The user account $new_user has been created successfully/, 'Account created');
        }
    }

    return unless $created;

    $sel->click_ok('delete');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Confirm deletion of user $new_user");
    $sel->click_ok('delete');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("User $new_user deleted");
}
