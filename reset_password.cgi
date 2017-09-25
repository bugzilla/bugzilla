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
use Bugzilla::Util qw( bz_crypt trim );
use Data::Dumper;

my $cgi          = Bugzilla->cgi;
my $user         = Bugzilla->login(LOGIN_REQUIRED);
my $template     = Bugzilla->template;
my $dbh          = Bugzilla->dbh;
my $prev_url     = $cgi->param('prev_url');
my $prev_url_sig = $cgi->param('prev_url_sig');
my $sig_type     = 'prev_url:' . $user->id;
my $prev_url_ok  = check_hash_sig($sig_type, $prev_url_sig, $prev_url );

unless ($prev_url_ok) {
    open my $fh, '>', '/tmp/dump.pl' or die $!;
    print $fh Dumper([$prev_url, $prev_url_sig]);
    close $fh or die $!;
}

unless ($user->password_change_required) {
    ThrowUserError(
        'reset_password_denied',
        {
            prev_url_ok => $prev_url_ok,
            prev_url    => $prev_url,
        }
    );

}

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

    Bugzilla->assert_password_is_secure($password_1);
    Bugzilla->assert_passwords_match($password_1, $password_2);

    # update
    $dbh->bz_start_transaction;
    $user->set_password($password_1);
    $user->update({ keep_session => 1, keep_tokens => 1 });
    Bugzilla->logout(LOGOUT_KEEP_CURRENT);
    delete_token($token);
    $dbh->bz_commit_transaction;

    # done
    print $cgi->header();
    $template->process(
        'account/reset-password.html.tmpl',
        {
            message          => 'password_changed',
            prev_url         => $prev_url,
            prev_url_ok      => $prev_url_ok,
            password_changed => 1
        }
    ) || ThrowTemplateError( $template->error() );

}

else {
    my $token = issue_session_token('reset_password');

    print $cgi->header();
    $template->process(
        'account/reset-password.html.tmpl',
        {
            token        => $token,
            prev_url     => $prev_url,
            prev_url_ok  => $prev_url_ok,
            prev_url_sig => $prev_url_sig,
            sig_type => $sig_type,
        }
    ) || ThrowTemplateError( $template->error() );


}
