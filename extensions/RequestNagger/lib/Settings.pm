# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::RequestNagger::Settings;

use 5.10.1;
use strict;
use warnings;

use Bugzilla;
use List::MoreUtils qw( any );

use constant FIELDS => qw( reviews_only extended_period no_encryption );

sub new {
  my ($class, $user_id) = @_;

  my $dbh = Bugzilla->dbh;
  my $self = {user_id => $user_id};
  foreach my $row (@{
    $dbh->selectall_arrayref(
      "SELECT setting_name,setting_value FROM nag_settings WHERE user_id = ?",
      {Slice => {}}, $user_id)
  })
  {
    $self->{$row->{setting_name}} = $row->{setting_value};
  }

  return bless($self, $class);
}

sub reviews_only { exists $_[0]->{reviews_only} ? $_[0]->{reviews_only} : 0 }

sub extended_period {
  exists $_[0]->{extended_period} ? $_[0]->{extended_period} : 0;
}
sub no_encryption { exists $_[0]->{no_encryption} ? $_[0]->{no_encryption} : 0 }

sub set {
  my ($self, $field, $value) = @_;
  return unless any { $_ eq $field } FIELDS;
  $value = $value ? 1 : 0;

  my $dbh = Bugzilla->dbh;
  if (exists $self->{$field}) {
    $dbh->do(
      "UPDATE nag_settings SET setting_value=? WHERE user_id=? AND setting_name=?",
      undef, $value, $self->{user_id}, $field);
  }
  else {
    $dbh->do(
      "INSERT INTO nag_settings(user_id, setting_name, setting_value) VALUES (?, ?, ?)",
      undef, $self->{user_id}, $field, $value
    );
  }

  $self->{$field} = $value;
}

1;
