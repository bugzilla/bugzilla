#!/usr/bin/perl -wT
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Myk Melez <myk@mozilla.org>
#                 Frédéric Buclin <LpSolit@gmail.com>

use strict;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Token;
use Bugzilla::User;

use Date::Format;
use Date::Parse;

local our $cgi = Bugzilla->cgi;
local our $template = Bugzilla->template;
local our $vars = {};

my $action = $cgi->param('a');
my $token = $cgi->param('t');

Bugzilla->login(LOGIN_OPTIONAL);

# Throw an error if the form does not contain an "action" field specifying
# what the user wants to do.
$action || ThrowUserError('unknown_action');

Bugzilla::Token::CleanTokenTable();
my ($user_id, $date, $data, $tokentype) = Bugzilla::Token::GetTokenData($token);

# Requesting a new password is the single action which doesn't require a token.
# XXX Ideally, these checks should be done inside the subroutines themselves.
unless ($action eq 'reqpw') {
    $tokentype || ThrowUserError("token_does_not_exist");

    # Make sure the token is the correct type for the action being taken.
    my $error;
    if (grep($action eq $_ , qw(cfmpw cxlpw chgpw)) && $tokentype ne 'password') {
        $error = 'wrong_token_for_changing_passwd';
    }
    elsif ($action eq 'cxlem'
           && ($tokentype ne 'emailold' && $tokentype ne 'emailnew'))
    {
        $error = 'wrong_token_for_cancelling_email_change';
    }
    elsif (grep($action eq $_ , qw(cfmem chgem)) && $tokentype ne 'emailnew') {
        $error = 'wrong_token_for_confirming_email_change';
    }
    elsif ($action =~ /^(request|confirm|cancel)_new_account$/
           && $tokentype ne 'account')
    {
        $error = 'wrong_token_for_creating_account';
    }

    if ($error) {
        Bugzilla::Token::Cancel($token, $error);
        ThrowUserError($error);
    }
}

if ($action eq 'reqpw') {
    requestChangePassword();
}
elsif ($action eq 'cfmpw') {
    confirmChangePassword($token);
}
elsif ($action eq 'cxlpw') {
    cancelChangePassword($token);
}
elsif ($action eq 'chgpw') {
    changePassword($user_id, $token);
}
elsif ($action eq 'cfmem') {
    confirmChangeEmail($token);
}
elsif ($action eq 'cxlem') {
    cancelChangeEmail($user_id, $data, $tokentype, $token);
}
elsif ($action eq 'chgem') {
    changeEmail($user_id, $data, $token);
}
elsif ($action eq 'request_new_account') {
    request_create_account($date, $data, $token);
}
elsif ($action eq 'confirm_new_account') {
    confirm_create_account($data, $token);
}
elsif ($action eq 'cancel_new_account') {
    cancel_create_account($data, $token);
}
else {
    ThrowUserError('unknown_action', {action => $action});
}

exit;

################################################################################
# Functions
################################################################################

# If the user is requesting a password change, make sure they submitted
# their login name and it exists in the database, and that the DB module is in
# the list of allowed verification methods.
sub requestChangePassword {
    # check verification methods
    Bugzilla->user->authorizer->can_change_password
      || ThrowUserError("password_change_requests_not_allowed");

    my $login_name = $cgi->param('loginname')
      or ThrowUserError("login_needed_for_password_change");

    validate_email_syntax($login_name)
      || ThrowUserError('illegal_email_address', {addr => $login_name});

    my $user = Bugzilla::User->check($login_name);

    # Make sure the user account is active.
    if (!$user->is_enabled) {
        ThrowUserError('account_disabled',
                       {disabled_reason => get_text('account_disabled', {account => $login_name})});
    }

    Bugzilla::Token::IssuePasswordToken($user);

    $vars->{'message'} = "password_change_request";

    print $cgi->header();
    $template->process("global/message.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}

sub confirmChangePassword {
    my $token = shift;
    $vars->{'token'} = $token;

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

# If the user is changing their password, make sure they submitted a new
# password and that the new password is valid.
sub changePassword {
    my ($user_id, $token) = @_;

    my $password = $cgi->param('password');
    (defined $password && defined $cgi->param('matchpassword'))
      || ThrowUserError("require_new_password");

    validate_password($password, $cgi->param('matchpassword'));
    # Make sure that these never show up in the UI under any circumstances.
    $cgi->delete('password', 'matchpassword');

    my $user = Bugzilla::User->check({ id => $user_id });
    $user->set_password($password);
    $user->update();
    delete_token($token);

    Bugzilla->logout_user_by_id($user_id);

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
    my ($userid, $eventdata, $token) = @_;
    my $dbh = Bugzilla->dbh;

    my ($old_email, $new_email) = split(/:/,$eventdata);

    # Check the user entered the correct old email address
    if (lc($cgi->param('email')) ne lc($old_email)) {
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
    delete_token($token);
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
    my ($userid, $eventdata, $tokentype, $token) = @_;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    my ($old_email, $new_email) = split(/:/,$eventdata);

    if ($tokentype eq "emailold") {
        $vars->{'message'} = "emailold_change_canceled";
        my $user = Bugzilla::User->check({ id => $userid });

        # check to see if it has been altered
        if ($user->login ne $old_email) {
            $user->set_login($old_email);
            $user->update();
            # email has changed, so rederive groups
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
    my ($date, $login_name, $token) = @_;

    $vars->{'token'} = $token;
    $vars->{'email'} = $login_name . Bugzilla->params->{'emailsuffix'};
    $vars->{'expiration_ts'} = ctime(str2time($date) + MAX_TOKEN_AGE * 86400);

    print $cgi->header();
    $template->process('account/email/confirm-new.html.tmpl', $vars)
      || ThrowTemplateError($template->error());
}

sub confirm_create_account {
    my ($login_name, $token) = @_;

    my $password = $cgi->param('passwd1') || '';
    validate_password($password, $cgi->param('passwd2') || '');
    # Make sure that these never show up anywhere in the UI.
    $cgi->delete('passwd1', 'passwd2');

    my $otheruser = Bugzilla::User->create({
        login_name => $login_name, 
        realname   => $cgi->param('realname'), 
        cryptpassword => $password});

    # Now delete this token.
    delete_token($token);

    # Let the user know that his user account has been successfully created.
    $vars->{'message'} = 'account_created';
    $vars->{'otheruser'} = $otheruser;

    # Log in the new user using credentials he just gave.
    $cgi->param('Bugzilla_login', $otheruser->login);
    $cgi->param('Bugzilla_password', $password);
    Bugzilla->login(LOGIN_OPTIONAL);

    print $cgi->header();

    $template->process('index.html.tmpl', $vars)
      || ThrowTemplateError($template->error());
}

sub cancel_create_account {
    my ($login_name, $token) = @_;

    $vars->{'message'} = 'account_creation_canceled';
    $vars->{'account'} = $login_name;
    Bugzilla::Token::Cancel($token, $vars->{'message'});

    print $cgi->header();
    $template->process('global/message.html.tmpl', $vars)
      || ThrowTemplateError($template->error());
}
