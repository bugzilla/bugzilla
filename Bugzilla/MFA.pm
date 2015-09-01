# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::MFA;
use strict;

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

# during-login verification
sub check_login {}


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

sub property_delete_all {
    my ($self) = @_;
    Bugzilla->dbh->do(
        "DELETE FROM profile_mfa WHERE user_id",
        undef, $self->{user}->id);
}

1;
