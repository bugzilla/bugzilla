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
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Token;
use Bugzilla::User;

use Date::Format;
use Date::Parse;
use JSON qw( decode_json );

local our $dbh = Bugzilla->dbh;
local our $cgi = Bugzilla->cgi;
local our $template = Bugzilla->template;
local our $vars = {};

my $action = $cgi->param('a');
my $token = $cgi->param('t');

Bugzilla->login(LOGIN_OPTIONAL);

################################################################################
# Data Validation / Security Authorization
################################################################################

# Throw an error if the form does not contain an "action" field specifying
# what the user wants to do.
$action || ThrowUserError('unknown_action');

# If a token was submitted, make sure it is a valid token that exists in the
# database and is the correct type for the action being taken.
if ($token) {
  Bugzilla::Token::CleanTokenTable();

  # It's safe to detaint the token as it's used in a placeholder.
  trick_taint($token);

  # Make sure the token exists in the database.
  my ($db_token, $tokentype) = $dbh->selectrow_array('SELECT token, tokentype FROM tokens
                                                       WHERE token = ?', undef, $token);
  (defined $db_token && $db_token eq $token)
    || ThrowUserError("token_does_not_exist");

  # Make sure the token is the correct type for the action being taken.
  if ( grep($action eq $_ , qw(cfmpw cxlpw chgpw)) && $tokentype ne 'password' ) {
    Bugzilla::Token::Cancel($token, "wrong_token_for_changing_passwd");
    ThrowUserError("wrong_token_for_changing_passwd");
  }
  if ( ($action eq 'cxlem')
      && (($tokentype ne 'emailold') && ($tokentype ne 'emailnew')) ) {
    Bugzilla::Token::Cancel($token, "wrong_token_for_cancelling_email_change");
    ThrowUserError("wrong_token_for_cancelling_email_change");
  }
  if ( grep($action eq $_ , qw(cfmem chgem))
      && ($tokentype ne 'emailnew') ) {
    Bugzilla::Token::Cancel($token, "wrong_token_for_confirming_email_change");
    ThrowUserError("wrong_token_for_confirming_email_change");
  }
  if (($action =~ /^(request|confirm|cancel)_new_account$/)
      && ($tokentype ne 'account'))
  {
      Bugzilla::Token::Cancel($token, 'wrong_token_for_creating_account');
      ThrowUserError('wrong_token_for_creating_account');
  }
  if (substr($action, 0, 4) eq 'mfa_' && $tokentype ne 'session.short') {
      Bugzilla::Token::Cancel($token, 'wrong_token_for_mfa');
      ThrowUserError('wrong_token_for_mfa');
  }
}


# If the user is requesting a password change, make sure they submitted
# their login name and it exists in the database, and that the DB module is in
# the list of allowed verification methods.
my $user_account;
if ( $action eq 'reqpw' ) {
    my $login_name = $cgi->param('loginname')
                       || ThrowUserError("login_needed_for_password_change");

    # check verification methods
    unless (Bugzilla->user->authorizer->can_change_password) {
        ThrowUserError("password_change_requests_not_allowed");
    }

    # Check the hash token to make sure this user actually submitted
    # the forgotten password form.
    my $token = $cgi->param('token');
    check_hash_token($token, ['reqpw']);

    validate_email_syntax($login_name)
        || ThrowUserError('illegal_email_address', {addr => $login_name});

    $user_account = Bugzilla::User->check($login_name);

    # Make sure the user account is active.
    if (!$user_account->is_enabled) {
        ThrowUserError('account_disabled',
                       {disabled_reason => get_text('account_disabled', {account => $login_name})});
    }
}

# If the user is changing their password, make sure they submitted a new
# password and that the new password is valid.
my $password;
if ( $action eq 'chgpw' ) {
    $password = $cgi->param('password');
    my $matchpassword = $cgi->param('matchpassword');
    ThrowUserError("require_new_password")
        unless defined $password && defined $matchpassword;

    Bugzilla->assert_password_is_secure($password);
    Bugzilla->assert_passwords_match($password, $matchpassword);

    # Make sure that these never show up in the UI under any circumstances.
    $cgi->delete('password', 'matchpassword');
}

################################################################################
# Main Body Execution
################################################################################

# All calls to this script should contain an "action" variable whose value
# determines what the user wants to do.  The code below checks the value of
# that variable and runs the appropriate code.

if ($action eq 'reqpw') {
    requestChangePassword($user_account);
} elsif ($action eq 'cfmpw') {
    confirmChangePassword($token);
} elsif ($action eq 'cxlpw') {
    cancelChangePassword($token);
} elsif ($action eq 'chgpw') {
    changePassword($token, $password);
} elsif ($action eq 'cfmem') {
    confirmChangeEmail($token);
} elsif ($action eq 'cxlem') {
    cancelChangeEmail($token);
} elsif ($action eq 'chgem') {
    changeEmail($token);
} elsif ($action eq 'request_new_account') {
    request_create_account($token);
} elsif ($action eq 'confirm_new_account') {
    confirm_create_account($token);
} elsif ($action eq 'cancel_new_account') {
    cancel_create_account($token);
} elsif ($action eq 'mfa_l') {
    verify_mfa_login($token);
} elsif ($action eq 'mfa_p') {
    verify_mfa_password($token);
} else {
    ThrowUserError('unknown_action', {action => $action});
}

exit;

################################################################################
# Functions
################################################################################

sub requestChangePassword {
    my ($user) = @_;
    Bugzilla::Token::IssuePasswordToken($user);

    $vars->{'message'} = "password_change_request";

    print $cgi->header();
    $template->process("global/message.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}

sub confirmChangePassword {
    my $token = shift;
    $vars->{'token'} = $token;

    my ($user_id) = Bugzilla::Token::GetTokenData($token);
    $vars->{token_user} = Bugzilla::User->check({ id => $user_id, cache => 1 });

    print $cgi->header();
    $template->process("account/password/set-forgotten-password.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}

sub cancelChangePassword {
    my $token = shift;
    $vars->{'message'} = "password_change_canceled";
    Bugzilla::Token::Cancel($token, $vars->{'message'});

    print $cgi->header();
    $template->process("global/message.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}

sub changePassword {
    my ($token, $password) = @_;
    my $dbh = Bugzilla->dbh;

    my ($user_id) = Bugzilla::Token::GetTokenData($token);
    my $user = Bugzilla::User->check({ id => $user_id });

    if ($user->mfa) {
        $user->mfa_provider->verify_prompt({
            user     => $user,
            reason   => 'Setting your password',
            password => $password,
            token    => $token,
            postback => {
                action      => 'token.cgi',
                token_field => 't',
                fields      => {
                    a => 'mfa_p',
                },
            },
        });
    }
    else {
        set_user_password($token, $user, $password);
    }
}

sub verify_mfa_password {
    my $token = shift;
    my ($user, $event) = mfa_event_from_token($token);
    set_user_password($event->{token}, $user, $event->{password});
}

sub set_user_password {
    my ($token, $user, $password) = @_;

    $user->set_password($password);
    $user->update();
    delete_token($token);
    $dbh->do("DELETE FROM tokens WHERE userid = ? AND tokentype = 'password'", undef, $user->id);

    Bugzilla->logout_user_by_id($user->id);

    $vars->{'message'} = "password_changed";

    print $cgi->header();
    $template->process("global/message.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}

sub confirmChangeEmail {
    my $token = shift;
    $vars->{'token'} = $token;

    print $cgi->header();
    $template->process("account/email/confirm.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}

sub changeEmail {
    my $token = shift;
    my $dbh = Bugzilla->dbh;

    # Get the user's ID from the tokens table.
    my ($userid, $eventdata) = $dbh->selectrow_array(
                                 q{SELECT userid, eventdata FROM tokens
                                   WHERE token = ?}, undef, $token);
    my ($old_email, $new_email) = split(/:/,$eventdata);

    # Check the user entered the correct old email address
    if(lc($cgi->param('email')) ne lc($old_email)) {
        ThrowUserError("email_confirmation_failed");
    }
    # The new email address should be available as this was
    # confirmed initially so cancel token if it is not still available
    if (! is_available_username($new_email,$old_email)) {
        $vars->{'email'} = $new_email; # Needed for Bugzilla::Token::Cancel's mail
        Bugzilla::Token::Cancel($token, "account_exists", $vars);
        ThrowUserError("account_exists", { email => $new_email } );
    }

    # Update the user's login name in the profiles table and delete the token
    # from the tokens table.
    $dbh->bz_start_transaction();
    $dbh->do(q{UPDATE   profiles
               SET      login_name = ?
               WHERE    userid = ?},
             undef, ($new_email, $userid));
    Bugzilla->memcached->clear({ table => 'profiles', id => $userid });
    $dbh->do('DELETE FROM tokens WHERE token = ?', undef, $token);
    $dbh->do(q{DELETE FROM tokens WHERE userid = ?
               AND tokentype = 'emailnew'}, undef, $userid);

    # The email address has been changed, so we need to rederive the groups
    my $user = new Bugzilla::User($userid);
    $user->derive_regexp_groups;

    $dbh->bz_commit_transaction();

    # Return HTTP response headers.
    print $cgi->header();

    # Let the user know their email address has been changed.

    $vars->{'message'} = "login_changed";

    $template->process("global/message.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}

sub cancelChangeEmail {
    my $token = shift;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    # Get the user's ID from the tokens table.
    my ($userid, $tokentype, $eventdata) = $dbh->selectrow_array(
                              q{SELECT userid, tokentype, eventdata FROM tokens
                                WHERE token = ?}, undef, $token);
    my ($old_email, $new_email) = split(/:/,$eventdata);

    if($tokentype eq "emailold") {
        $vars->{'message'} = "emailold_change_canceled";

        my $actualemail = $dbh->selectrow_array(
                            q{SELECT login_name FROM profiles
                              WHERE userid = ?}, undef, $userid);

        # check to see if it has been altered
        if($actualemail ne $old_email) {
            # XXX - This is NOT safe - if A has change to B, another profile
            # could have grabbed A's username in the meantime.
            # The DB constraint will catch this, though
            $dbh->do(q{UPDATE   profiles
                       SET      login_name = ?
                       WHERE    userid = ?},
                     undef, ($old_email, $userid));
            Bugzilla->memcached->clear({ table => 'profiles', id => $userid });

            # email has changed, so rederive groups

            my $user = new Bugzilla::User($userid);
            $user->derive_regexp_groups;

            $vars->{'message'} = "email_change_canceled_reinstated";
        }
    }
    else {
        $vars->{'message'} = 'email_change_canceled'
     }

    $vars->{'old_email'} = $old_email;
    $vars->{'new_email'} = $new_email;
    Bugzilla::Token::Cancel($token, $vars->{'message'}, $vars);

    $dbh->do(q{DELETE FROM tokens WHERE userid = ?
               AND tokentype = 'emailold' OR tokentype = 'emailnew'},
             undef, $userid);

    $dbh->bz_commit_transaction();

    # Return HTTP response headers.
    print $cgi->header();

    $template->process("global/message.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}

sub request_create_account {
    my $token = shift;

    Bugzilla->user->check_account_creation_enabled;
    my (undef, $date, $login_name) = Bugzilla::Token::GetTokenData($token);
    $vars->{'token'} = $token;
    $vars->{'email'} = $login_name . Bugzilla->params->{'emailsuffix'};
    $vars->{'expiration_ts'} = ctime(str2time($date) + MAX_TOKEN_AGE * 86400);

    print $cgi->header();
    $template->process('account/email/confirm-new.html.tmpl', $vars)
      || ThrowTemplateError($template->error());
}

sub confirm_create_account {
    my $token = shift;

    Bugzilla->user->check_account_creation_enabled;
    my (undef, undef, $login_name) = Bugzilla::Token::GetTokenData($token);

    my $password1 = $cgi->param('passwd1');
    my $password2 = $cgi->param('passwd2');
    # Make sure that these never show up anywhere in the UI.
    $cgi->delete('passwd1', 'passwd2');
    Bugzilla->assert_password_is_secure($password1);
    Bugzilla->assert_passwords_match($password1, $password2);

    my $otheruser = Bugzilla::User->create({
        login_name => $login_name,
        realname   => scalar $cgi->param('realname'),
        cryptpassword => $password1});

    # Now delete this token.
    delete_token($token);

    # Let the user know that his user account has been successfully created.
    $vars->{'message'} = 'account_created';
    $vars->{'otheruser'} = $otheruser;

    # Log in the new user using credentials he just gave.
    $cgi->param('Bugzilla_login', $otheruser->login);
    $cgi->param('Bugzilla_password', $password1);
    Bugzilla->login(LOGIN_OPTIONAL);

    print $cgi->header();

    $template->process('index.html.tmpl', $vars)
      || ThrowTemplateError($template->error());
}

sub cancel_create_account {
    my $token = shift;

    my (undef, undef, $login_name) = Bugzilla::Token::GetTokenData($token);

    $vars->{'message'} = 'account_creation_canceled';
    $vars->{'account'} = $login_name;
    Bugzilla::Token::Cancel($token, $vars->{'message'});

    print $cgi->header();
    $template->process('global/message.html.tmpl', $vars)
      || ThrowTemplateError($template->error());
}

sub verify_mfa_login {
    my $token = shift;
    my ($user, $event) = mfa_event_from_token($token);
    $user->authorizer->mfa_verified($user, $event);
    print Bugzilla->cgi->redirect($event->{url} // 'index.cgi');
    exit;
}

sub mfa_event_from_token {
    my $token = shift;

    # create user from token
    my ($user_id) = Bugzilla::Token::GetTokenData($token);
    my $user = Bugzilla::User->check({ id => $user_id, cache => 1 });

    # sanity check
    if (!$user->mfa) {
        delete_token($token);
        print Bugzilla->cgi->redirect('index.cgi');
        exit;
    }

    # verify
    my $event = $user->mfa_provider->verify_token($token);
    return ($user, $event);
}
