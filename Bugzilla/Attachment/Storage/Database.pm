# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::Storage::Database;

use 5.10.1;
use Moo;

with 'Bugzilla::Attachment::Storage::Base';

sub data_type { return 'database'; }

sub set_data {
  my ($self, $data) = @_;
  my $dbh = Bugzilla->dbh;
  my $sth
    = $dbh->prepare(
    "REPLACE INTO attach_data (id, thedata) VALUES (?, ?)"
    );
  $sth->bind_param(1, $self->attachment->id);
  $sth->bind_param(2, $data, $dbh->BLOB_TYPE);
  $sth->execute();
  return $self;
}

sub get_data {
  my ($self) = @_;
  my $dbh = Bugzilla->dbh;
  my ($data)
    = $dbh->selectrow_array("SELECT thedata FROM attach_data WHERE id = ?",
    undef, $self->attachment->id);
  return $data;
}

sub remove_data {
  my ($self) = @_;
  my $dbh = Bugzilla->dbh;
  $dbh->do("DELETE FROM attach_data WHERE id = ?", undef, $self->attachment->id);
  return $self;
}

sub data_exists {
  my ($self)   = @_;
  my $dbh      = Bugzilla->dbh;
  my ($exists) = $dbh->selectrow_array("SELECT 1 FROM attach_data WHERE id = ?",
    undef, $self->attachment->id);
  return !!$exists;
}

1;
