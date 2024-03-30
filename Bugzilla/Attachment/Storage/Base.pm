# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::Storage::Base;

use 5.10.1;
use Moo::Role;

use Types::Standard qw(Int);

requires qw(set_data get_data remove_data data_exists data_type);

has 'attach_id' => (
  is       => 'ro',
  required => 1,
  isa      => Int
);

sub set_class {
  my ($self) = @_;
  if ($self->data_exists()) {
    Bugzilla->dbh->do(
      "UPDATE attachment_storage_class SET storage_class = ? WHERE id = ?",
      undef, $self->data_type, $self->attach_id);
  }
  else {
    Bugzilla->dbh->do(
      "INSERT INTO attachment_storage_class (id, storage_class) VALUES (?, ?)",
      undef, $self->attach_id, $self->data_type);
  }
  return $self;
}

sub remove_class {
  my ($self) = @_;
  Bugzilla->dbh->do("DELETE FROM attachment_storage_class WHERE id = ?",
    undef, $self->attach_id);
  return $self;
}

1;
