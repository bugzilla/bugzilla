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
log_in($sel, $config, 'admin');

set_parameters(
  $sel,
  {
    "Administrative Policies" => {"allowuserdeletion-on" => undef},
    "User Authentication" =>
      {"createemailregexp" => {type => "text", value => '.*'}}
  }
);

# Set the password complexity to MIXED LETTERS.
# Password must contain at least one UPPER and one lowercase letter.
my @invalid_mixed_letter = qw(lowercase UPPERCASE 1234567890 123lowercase
  123UPPERCASE !@%&^lower !@&^UPPER);

check_passwords($sel, 'mixed_letters', \@invalid_mixed_letter,
  ['PaSSwOrd', '%9rT#j22S']);

# Set the password complexity to LETTERS AND NUMBERS.
# Passwords must contain at least one UPPER and one lower case letter and a number.
my @invalid_letter_number = (@invalid_mixed_letter, qw(lowerUPPER 123!@%^$));

check_passwords($sel, 'letters_numbers', \@invalid_letter_number,
  ['-UniCode6.3', 'UNO54sun']);

# Set the password complexity to LETTERS, NUMBERS AND SPECIAL CHARACTERS.
# Passwords must contain at least one letter, a number and a special character.
my @invalid_letter_number_splchar
  = (qw(!@%^&~* lowerUPPER123), @invalid_letter_number);

check_passwords(
  $sel,
  'letters_numbers_specialchars',
  \@invalid_letter_number_splchar,
  ['@gu731', 'HU%m70?']
);

# Set the password complexity to No Constraints.
check_passwords(
  $sel, 'no_constraints',
  ['12xY!',    'aaaaa'],
  ['aaaaaaaa', '>F12Xy?']
);

logout($sel);


sub check_passwords {
  my ($sel, $param, $invalid_passwords, $valid_passwords) = @_;

  set_parameters(
    $sel,
    {
      "User Authentication" =>
        {"password_complexity" => {type => "select", value => $param}}
    }
  );
  my $new_user = 'selenium-' . random_string(10) . '@bugzilla.org';

  go_to_admin($sel);
  $sel->click_ok("link=Users");
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is('Search users');
  $sel->click_ok('link=add a new user');
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is('Add user');
  $sel->type_ok('email', $new_user);

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
    if ($param eq 'mixed_letters') {
      ok(
        $error_msg =~ /UPPERCASE letter.*lowercase letter/,
        "Mixed letter password fails requirement: $password"
      );
    }
    elsif ($param eq 'letters_numbers') {
      ok(
        $error_msg =~ /UPPERCASE letter.*lowercase letter.*digit/,
        "Letter & Number password fails requirement: $password"
      );

    }
    elsif ($param eq 'letters_numbers_specialchars') {
      ok($error_msg =~ /letter.*special character.*digit/,
        "Letter, Number & Special Character password fails requirement: $password");
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
      ok($msg =~ /The user account $new_user has been created successfully/,
        'Account created');
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
