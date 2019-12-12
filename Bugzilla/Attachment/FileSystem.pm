# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::FileSystem;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants qw(bz_locations);

sub new {
  return bless({}, shift);
}

sub store {
  my ($self, $attach_id, $data) = @_;
  my $path = _local_path($attach_id);
  mkdir($path, 0770) unless -d $path;
  open(my $fh, '>', _local_file($attach_id));
  binmode($fh);
  print $fh $data;
  close($fh);
}

sub retrieve {
  my ($self, $attach_id) = @_;
  if (open(my $fh, '<', _local_file($attach_id))) {
    local $/;
    binmode($fh);
    my $data = <$fh>;
    close($fh);
    return $data;
  }
  return undef;
}

sub remove {
  my ($self, $attach_id) = @_;
  unlink(_local_file($attach_id));
}

sub exists {
  my ($self, $attach_id) = @_;
  return -e _local_file($attach_id);
}

sub _local_path {
  my ($attach_id) = @_;
  my $hash = sprintf('group.%03d', $attach_id % 1000);
  return bz_locations()->{attachdir} . '/' . $hash;
}

sub _local_file {
  my ($attach_id) = @_;
  return _local_path($attach_id) . '/attachment.' . $attach_id;
}

1;
