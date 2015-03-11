#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Token;

# Just in case someone already has an account, let them get the correct footer
# on an error message. The user is logged out just after the account is
# actually created.
my $user = Bugzilla->login(LOGIN_OPTIONAL);
my $cgi = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars = { doc_section => 'using/creating-an-account.html' };

print $cgi->header();

my $login = $cgi->param('login');
my $request_new_password = $cgi->param('request_new_password');

if ($request_new_password) {
    $template->process('account/request-new-password.html.tmpl', $vars)
      || ThrowTemplateError($template->error());
}
elsif (defined($login)) {
    $user->check_account_creation_enabled;
    # Check the hash token to make sure this user actually submitted
    # the create account form.
    my $token = $cgi->param('token');
    check_hash_token($token, ['create_account']);

    $user->check_and_send_account_creation_confirmation($login);
    $vars->{'login'} = $login;

    $template->process("account/created.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}
else {
    # Show the standard "would you like to create an account?" form.
    $template->process('account/create.html.tmpl', $vars)
      || ThrowTemplateError($template->error());
}
