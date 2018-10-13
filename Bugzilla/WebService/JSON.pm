# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::JSON;
use 5.10.1;
use Moo;

use Bugzilla::Logging;
use Bugzilla::WebService::JSON::Box;
use JSON::MaybeXS;
use Scalar::Util qw(refaddr blessed);
use Package::Stash;

use constant Box => 'Bugzilla::WebService::JSON::Box';

has 'json' => (
  init_arg => undef,
  is       => 'lazy',
  handles  => {_encode => 'encode', _decode => 'decode'},
);

sub encode {
  my ($self, $value) = @_;
  return Box->new(json => $self, value => $value);
}

sub decode {
  my ($self, $box) = @_;

  if (blessed($box) && $box->isa(Box)) {
    return $box->value;
  }
  else {
    return $self->_decode($box);
  }
}

sub _build_json  { JSON::MaybeXS->new }

# delegation all the json options to the real json encoder.
{
  my @json_methods = qw(
    utf8 ascii pretty canonical
    allow_nonref allow_blessed convert_blessed
  );
  my $stash = Package::Stash->new(__PACKAGE__);
  foreach my $method (@json_methods) {
    my $symbol = '&' . $method;
    $stash->add_symbol(
      $symbol => sub {
        my $self = shift;
        $self->json->$method(@_);
        return $self;
      }
    );
  }
}


1;
