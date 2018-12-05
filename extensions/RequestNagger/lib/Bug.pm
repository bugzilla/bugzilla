# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::RequestNagger::Bug;

use 5.10.1;
use strict;
use warnings;

use parent qw(Bugzilla::Bug);
use feature 'state';

use Bugzilla::User;

sub short_desc {
  my ($self) = @_;
  return $self->{sanitise_bug} ? '(Secure bug)' : $self->SUPER::short_desc;
}

sub is_private {
  my ($self) = @_;
  if (!exists $self->{is_private}) {
    state $default_user //= Bugzilla::User->new();
    $self->{is_private} = !$default_user->can_see_bug($self);
  }
  return $self->{is_private};
}

sub tooltip {
  my ($self) = @_;
  my $tooltip = $self->bug_status;
  if ($self->bug_status eq 'RESOLVED') {
    $tooltip .= '/' . $self->resolution;
  }
  if (!$self->{sanitise_bug}) {
    $tooltip .= ' ' . $self->product . ' :: ' . $self->component;
  }
  return $tooltip;
}

1;
