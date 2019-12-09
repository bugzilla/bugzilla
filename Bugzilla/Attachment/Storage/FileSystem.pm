# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::Storage::FileSystem;

use 5.10.1;
use Moo;

use Bugzilla::Constants qw(bz_locations);

with 'Bugzilla::Attachment::Storage::Base';

sub data_type { return 'filesystem'; }

sub set_data {
  my ($self, $data) = @_;
  my $path = $self->_local_path();
  mkdir $path, 0770 unless -d $path;
  open my $fh, '>', $self->_local_file();
  binmode $fh;
  print $fh $data;
  close $fh;
  return $self;
}

sub get_data {
  my ($self) = @_;
  if (open my $fh, '<', $self->_local_file()) {
    local $/;
    binmode $fh;
    my $data = <$fh>;
    close $fh;
    return $data;
  }
}

sub remove_data {
  my ($self) = @_;
  unlink $self->_local_file();
  return $self;
}

sub data_exists {
  my ($self) = @_;
  return -e $self->_local_file();
}

sub _local_path {
  my ($self) = @_;
  my $hash = sprintf 'group.%03d', $self->attachment->id % 1000;
  return bz_locations()->{attachdir} . '/' . $hash;
}

sub _local_file {
  my ($self) = @_;
  return $self->_local_path() . '/attachment.' . $self->attachment->id;
}

1;
