# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::JSON::Box;
use 5.10.1;
use Moo;

use overload '${}' => 'value', '""' => 'to_string', fallback => 1;

has 'value' => (is => 'ro', required => 1);
has 'json'  => (is => 'ro', required => 1);
has 'label' => (is => 'lazy');
has 'encode' => (init_arg => undef, is => 'lazy', predicate => 'is_encoded');

sub TO_JSON {
  my ($self) = @_;

  return $self->to_string;
}

sub to_string {
  my ($self) = @_;

  return $self->is_encoded ? $self->encode : $self->label;
}

sub _build_encode {
  my ($self) = @_;

  return $self->json->_encode($self->value);
}

sub _build_label {
  my ($self) = @_;

  return "" . $self->value;
}

1;
