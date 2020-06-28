# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Users;
use Mojo::Base 'Mojolicious::Controller';

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Mailer qw(MessageToMTA);
use Date::Format qw(ctime);
use Scalar::Util qw(blessed);
use Bugzilla::User;
use List::Util qw(any);
use Try::Tiny;

sub setup_routes {
  my ($class, $r) = @_;

  $r->post('/signup/email')->to('Users#signup_email')->name('signup_email');
  $r->get('/signup/email/:token/verify')->to('Users#signup_email_verify')
    ->name('signup_email_verify');
  $r->post('/signup/email/:token/finish')->to('Users#signup_email_finish')
    ->name('signup_email_finish');
}

sub signup_email {
  my ($c) = @_;
  my $v = $c->validation;

  try {
    Bugzilla::User->new->check_account_creation_enabled;
    my $email_regexp = Bugzilla->params->{createemailregexp};
    $v->required('email')->like(qr/$email_regexp/);
    $v->csrf_protect;

    ThrowUserError('account_creation_restricted') unless $v->is_valid;

    my $email = $v->param('email');
    Bugzilla::User->check_login_name_for_creation($email);
    Bugzilla::Hook::process("user_verify_login", {login => $email});

    $c->issue_new_user_account_token($email);
    $c->render(handler => 'bugzilla');
  }
  catch {
    $c->bugzilla->error_page($_);
  };
}

sub signup_email_verify {
  my ($c) = @_;
  my $token = $c->stash->{token};
  my (undef, $issuedate, $email) = Bugzilla::Token::GetTokenData($token);

  if ($email) {
    $c->stash->{signup_token} = $token;
    $c->stash->{email}        = $email;
    $c->stash->{expires}      = $issuedate;
  }
  else {
    $c->stash->{missing_token} = 1;
  }

  $c->render(handler => 'bugzilla');
}

sub signup_email_finish {
  my ($c) = @_;
  my $v = $c->validation;
  try {
    $v->optional('create')->equal_to('create');
    $v->optional('cancel')->equal_to('cancel');
    $v->csrf_protect;
    $v->required('signup_token')->size(22);

    my $token = $v->param('signup_token');
    if ($v->is_valid) {
      my (undef, undef, $email) = Bugzilla::Token::GetTokenData($token);

      $v->error('signup_token', ['invalid_token']) unless $email;

      if ($v->is_valid && $v->param('create') eq 'create') {
        $v->optional('realname')->size(1, 255);
        $v->required('etiquette');
        $v->required('password')->size(8, 100);
        $v->required('password_confirm')->size(8, 100);
        if ($v->is_valid && $v->param('password') ne $v->param('password_confirm')) {
          $v->error('password_confirm', ['password_mismatch']);
          $v->error('password', ['password_mismatch']);
        }
        if ($v->is_valid) {
          my $new_user = Bugzilla::User->create({
            login_name    => $email,
            realname      => $v->param('realname'),
            cryptpassword => $v->param('password'),
          });
          $c->persist_login($new_user, 'signup');
          $c->redirect_to('/home');
        }
      }
      elsif ($v->is_valid && $v->param('cancel') eq 'cancel') {
        my (undef, undef, $email) = Bugzilla::Token::GetTokenData($token);
        my $vars = {};
        $vars->{'message'} = 'account_creation_canceled';
        $vars->{'account'} = $email;
        Bugzilla::Token::Cancel($token, $vars->{'message'});
      }
    }
    ThrowUserError('validation', { v => $v });
  }
  catch {
    $c->bugzilla->error_page($_);
  };
}

# This is adapted from issue_new_user_account_token from Bugzilla/Token.pm
# Creates and sends a token to create a new user account.
# It assumes that the login has the correct format and is not already in use.
sub issue_new_user_account_token {
  my ($c, $email) = @_;
  my $dbh = Bugzilla->dbh;

  # Is there already a pending request for this login name? If yes, do not throw
  # an error because the user may have lost their email with the token inside.
  # But to prevent using this way to mailbomb an email address, make sure
  # the last request is at least 10 minutes old before sending a new email.

  my $pending_requests = $dbh->selectrow_array(
    'SELECT COUNT(*)
           FROM tokens
          WHERE tokentype = ?
                AND ' . $dbh->sql_istrcmp('eventdata', '?') . '
                AND issuedate > '
      . $dbh->sql_date_math('NOW()', '-', 10, 'MINUTE'), undef, ('signup', $email)
  );

  ThrowUserError('too_soon_for_new_token', {'type' => 'signup'})
    if $pending_requests;

  my ($token, $token_ts)
    = Bugzilla::Token::_create_token(undef, 'signup', $email);

  $c->stash->{email}   = $email . Bugzilla->params->{'emailsuffix'};
  $c->stash->{expires} = ctime($token_ts + MAX_TOKEN_AGE * 86400);
  $c->stash->{verify_url}
    = $c->url_for('signup_email_verify', token => $token)->to_abs;

  my $message = $c->render_to_string(
    handler => 'bugzilla',
    format  => 'txt',
    variant => 'email'
  );
  WARN("Email: is\n$message");
  MessageToMTA($message->to_string);
}

# This is adapted from persist_login in Bugzilla/Auth/Persist/Cookie.pm
sub persist_login {
  my ($c, $user, $auth_method) = @_;
  my $dbh = Bugzilla->dbh;

  $dbh->bz_start_transaction();

  my $login_cookie
    = Bugzilla::Token::GenerateUniqueToken('logincookies', 'cookie');

  my $ip_addr = $c->forwarded_for;

  $dbh->do(
    'INSERT INTO logincookies (cookie, userid, ipaddr, lastused)
    VALUES (?, ?, ?, NOW())', undef, $login_cookie, $user->id, $ip_addr
  );

  # Issuing a new cookie is a good time to clean up the old
  # cookies.
  $dbh->do("DELETE FROM logincookies WHERE lastused < "
      . $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', MAX_LOGINCOOKIE_AGE, 'DAY'));

  $dbh->bz_commit_transaction();

  my %cookie_attr = (httponly => 1, path => '/', expires => time + 604800);

  if (Bugzilla->localconfig->urlbase =~ /^https/) {
    $cookie_attr{secure} = 1;
  }

  $c->cookie('Bugzilla_login',       $user->id,     \%cookie_attr);
  $c->cookie('Bugzilla_logincookie', $login_cookie, \%cookie_attr);

  my $securemail_groups
    = Bugzilla->can('securemail_groups')
    ? Bugzilla->securemail_groups
    : ['admin'];

  if (any { $user->in_group($_) } @$securemail_groups) {
    $auth_method //= 'unknown';

    Bugzilla->audit(
      sprintf "successful login of %s from %s using \"%s\", authenticated by %s",
      $user->login, $ip_addr, $c->req->headers->user_agent // '', $auth_method);
  }

  return $login_cookie;
}


1;
