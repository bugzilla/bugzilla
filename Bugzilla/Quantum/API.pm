# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::API;
use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

sub user_profile {
  my ($self) = @_;

  my $user = $self->bugzilla->oauth('user:read');
  if ($user && $user->id) {
    $self->render(
      json => {
        id     => $user->id,
        name   => $user->name,
        login  => $user->login,
        nick   => $user->nick,
        groups => [map { $_->name } @{$user->groups}],
      }
    );
  }
  else {
    $self->render( status => 401, text => 'Unauthorized');
  }
}

1;
