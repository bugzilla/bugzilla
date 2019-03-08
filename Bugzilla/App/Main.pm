# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Main;
use Mojo::Base 'Mojolicious::Controller';

use Bugzilla::Error;
use Try::Tiny;
use Bugzilla::Constants;

sub setup_routes {
  my ($class, $r) = @_;

  $r->any('/')->to('Main#root');

  $r->get('/testagent.cgi')->to('Main#testagent');

  $r->add_type('hex32' => qr/[[:xdigit:]]{32}/);
  $r->post('/announcement/hide/<checksum:hex32>')->to('Main#announcement_hide');
}

sub root {
  my ($c) = @_;
  $c->res->headers->cache_control('public, max-age=3600, immutable');
  $c->render(handler => 'bugzilla');
}

sub testagent {
  my ($self) = @_;
  $self->render(text => "OK Mojolicious");
}

sub announcement_hide {
  my ($self) = @_;
  my $checksum = $self->param('checksum');
  if ($checksum && $checksum =~ /^[[:xdigit:]]{32}$/) {
    $self->session->{announcement_checksum} = $checksum;
  }
  $self->render(json => {});
}

1;
