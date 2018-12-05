# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::MFA;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::RNG qw( irand );
use Bugzilla::Token
  qw( issue_short_lived_session_token set_token_extra_data get_token_extra_data delete_token );
use Bugzilla::Util qw( trick_taint );

sub new {
  my ($class, $user) = @_;
  return bless({user => $user}, $class);
}

sub new_from {
  my ($class, $user, $mfa) = @_;
  $mfa //= '';
  if ($mfa eq 'TOTP') {
    require Bugzilla::MFA::TOTP;
    return Bugzilla::MFA::TOTP->new($user);
  }
  elsif ($mfa eq 'Duo' && Bugzilla->params->{duo_host}) {
    require Bugzilla::MFA::Duo;
    return Bugzilla::MFA::Duo->new($user);
  }
  else {
    require Bugzilla::MFA::Dummy;
    return Bugzilla::MFA::Dummy->new($user);
  }
}

# abstract methods

# called during enrollment
sub enroll { }

# api call, returns required data to user-prefs enrollment page
sub enroll_api { }

# called after the user has confirmed enrollment
sub enrolled { }

# display page with verification prompt
sub prompt { }

# throws errors if code is invalid
sub check { }

# if true verifcation can happen inline (during enrollment/pref changes)
# if false then the mfa provider requires an intermediate verification page
sub can_verify_inline {0}

# verification

sub verify_prompt {
  my ($self, $event) = @_;
  my $user = delete $event->{user} // Bugzilla->user;

  # generate token and attach mfa data
  my $token = issue_short_lived_session_token('mfa', $user);
  set_token_extra_data($token, $event);

  # trigger provider verification
  my $token_field = $event->{postback}->{token_field} // 'mfa_token';
  $event->{postback}->{fields}->{$token_field} = $token;
  $self->prompt($event);
  exit;
}

sub verify_token {
  my ($self, $token) = @_;

  # check token
  my ($user_id) = Bugzilla::Token::GetTokenData($token);
  my $user = Bugzilla::User->check({id => $user_id, cache => 1});

  # verify mfa
  $self->verify_check(Bugzilla->input_params);

  # return event data
  my $event = get_token_extra_data($token);
  delete_token($token);
  if (!$event) {
    print Bugzilla->cgi->redirect('index.cgi');
    exit;
  }
  return $event;
}

sub verify_check {
  my ($self, $params) = @_;
  $params->{code} //= '';

  # recovery code verification
  if (length($params->{code}) == 9) {
    my $code = $params->{code};
    foreach my $i (1 .. 10) {
      my $key = "recovery.$i";
      if (($self->property_get($key) // '') eq $code) {
        $self->property_delete($key);
        return;
      }
    }
  }

  # mfa verification
  $self->check($params);
}

# methods

sub generate_recovery_codes {
  my ($self) = @_;

  my @codes;
  foreach my $i (1 .. 10) {

    # generate 9 digit code
    my $code;
    $code .= irand(10) for 1 .. 9;
    push @codes, $code;

    # store (replacing existing)
    $self->property_set("recovery.$i", $code);
  }

  return \@codes;
}

# helpers

sub property_get {
  my ($self, $name) = @_;
  trick_taint($name);
  return
    scalar Bugzilla->dbh->selectrow_array(
    "SELECT value FROM profile_mfa WHERE user_id = ? AND name = ?",
    undef, $self->{user}->id, $name);
}

sub property_set {
  my ($self, $name, $value) = @_;
  trick_taint($name);
  trick_taint($value);
  Bugzilla->dbh->do(
    "INSERT INTO profile_mfa (user_id, name, value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = ?",
    undef, $self->{user}->id, $name, $value, $value
  );
}

sub property_delete {
  my ($self, $name) = @_;
  trick_taint($name);
  Bugzilla->dbh->do("DELETE FROM profile_mfa WHERE user_id = ? AND name = ?",
    undef, $self->{user}->id, $name);
}

1;
