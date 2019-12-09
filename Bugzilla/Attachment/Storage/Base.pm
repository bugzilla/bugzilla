# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::Storage::Base;

use 5.10.1;
use Moo::Role;

use Type::Utils qw(class_type);

requires qw(set_data get_data remove_data data_exists data_type);

has 'attachment' => (
  is       => 'ro',
  required => 1,
  isa      => class_type({class => 'Bugzilla::Attachment'})
);

sub set_class {
  my ($self) = @_;
  Bugzilla->dbh->do(
    "REPLACE INTO attachment_storage_class (id, storage_class) VALUES (?, ?)",
    undef, $self->attachment->id, $self->data_type);
  return $self;
}

sub remove_class {
  my ($self) = @_;
  Bugzilla->dbh->do("DELETE FROM attachment_storage_class WHERE id = ?",
    undef, $self->attachment->id);
  return $self;
}

1;
