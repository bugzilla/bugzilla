# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Role::Storable;

use 5.10.1;
use strict;
use warnings;
use Role::Tiny;

requires 'flatten_to_hash';

sub STORABLE_freeze {
  my ($self, $cloning) = @_;
  return if $cloning;    # Regular default serialization
  return '', $self->flatten_to_hash;
}

sub STORABLE_thaw {
  my ($self, $cloning, $serialized, $frozen) = @_;
  return if $cloning;
  %$self = %$frozen;
}

1;
