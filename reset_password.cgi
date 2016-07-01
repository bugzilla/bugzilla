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

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Token;
use Bugzilla::User qw( validate_password );
use Bugzilla::Util qw( bz_crypt );

my $cgi = Bugzilla->cgi;
my $user = Bugzilla->login(LOGIN_REQUIRED);
my $template = Bugzilla->template;
my $dbh = Bugzilla->dbh;

if ($cgi->param('do_save')) {
    my $token = $cgi->param('token');
    check_token_data($token, 'reset_password');

    my $old_password = $cgi->param('old_password') // '';
    my $password_1 = $cgi->param('new_password1') // '';
    my $password_2 = $cgi->param('new_password2') // '';

    # make sure passwords never show up in the UI
    foreach my $field (qw( old_password new_password1 new_password2 )) {
        $cgi->delete($field);
    }

    # validation
    my $old_crypt_password = $user->cryptpassword;
    if (bz_crypt($old_password, $old_crypt_password) ne $old_crypt_password) {
        ThrowUserError('old_password_incorrect');
    }
    if ($password_1 eq '' || $password_2 eq '') {
        ThrowUserError('new_password_missing');
    }
    if ($old_password eq $password_1) {
        ThrowUserError('new_password_same');
    }
    validate_password($password_1, $password_2);

    # update
    $dbh->bz_start_transaction;
    $user->set_password($password_1);
    $user->update({ keep_session => 1, keep_tokens => 1 });
    Bugzilla->logout(LOGOUT_KEEP_CURRENT);
    delete_token($token);
    $dbh->bz_commit_transaction;

    # done
    print $cgi->header();
    $template->process('index.html.tmpl', { message => 'password_changed' })
        || ThrowTemplateError($template->error());
}

else {
    my $token = issue_session_token('reset_password');

    print $cgi->header();
    $template->process('account/reset-password.html.tmpl', { token => $token })
        || ThrowTemplateError($template->error());
}
