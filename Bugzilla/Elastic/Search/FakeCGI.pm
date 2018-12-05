# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Elastic::Search::FakeCGI;
use 5.10.1;
use Moo;
use namespace::clean;

has 'params' => (is => 'ro', default => sub { {} });

# we pretend to be Bugzilla::CGI at times.
sub canonicalise_query {
  return Bugzilla::CGI::canonicalise_query(@_);
}

sub delete {
  my ($self, $key) = @_;
  delete $self->params->{$key};
}

sub redirect {
  my ($self, @args) = @_;

  Bugzilla::Elastic::Search::Redirect->throw(redirect_args => \@args);
}

sub param {
  my ($self, $key, $val, @rest) = @_;
  if (@_ > 3) {
    $self->params->{$key} = [$val, @rest];
  }
  elsif (@_ == 3) {
    $self->params->{$key} = $val;
  }
  elsif (@_ == 2) {
    return $self->params->{$key};
  }
  else {
    return $self->params;
  }
}

1;
