# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::MFA;
use strict;

use Bugzilla::Token qw( issue_short_lived_session_token set_token_extra_data get_token_extra_data delete_token );

sub new {
    my ($class, $user) = @_;
    return bless({ user => $user }, $class);
}

# abstract methods

# api call, returns required data to user-prefs enrollment page
sub enroll {}

# called after the user has confirmed enrollment
sub enrolled {}

# display page with verification prompt
sub prompt {}

# throws errors if code is invalid
sub check {}

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

sub verify_check {
    my ($self, $token) = @_;

    # check token
    my ($user_id) = Bugzilla::Token::GetTokenData($token);
    my $user = Bugzilla::User->check({ id => $user_id, cache => 1 });

    # mfa verification
    $self->check(Bugzilla->input_params);

    # return event data
    my $event = get_token_extra_data($token);
    delete_token($token);
    if (!$event) {
        print Bugzilla->cgi->redirect('index.cgi');
        exit;
    }
    return $event;
}

# helpers

sub property_get {
    my ($self, $name) = @_;
    return scalar Bugzilla->dbh->selectrow_array(
        "SELECT value FROM profile_mfa WHERE user_id = ? AND name = ?",
        undef, $self->{user}->id, $name);
}

sub property_set {
    my ($self, $name, $value) = @_;
    Bugzilla->dbh->do(
        "INSERT INTO profile_mfa (user_id, name, value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = ?",
        undef, $self->{user}->id, $name, $value, $value);
}

sub property_delete {
    my ($self, $name) = @_;
    Bugzilla->dbh->do(
        "DELETE FROM profile_mfa WHERE user_id = ? AND name = ?",
        undef, $self->{user}->id, $name);
}

1;
