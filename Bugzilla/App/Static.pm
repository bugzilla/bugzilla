# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Static;
use Mojo::Base 'Mojolicious::Static';
use Bugzilla::Constants qw(bz_locations);

my $LEGACY_RE = qr{
    ^ (?:static/v(?<version>[0-9]+\.[0-9]+)/) ?
    (?<file>(?:extensions/[^/]+/web|(?:image|skin|j|graph)s)/.+)
    $
}xs;

sub serve {
  my ($self, $c, $rel) = @_;

  if ($rel =~ $LEGACY_RE) {
    local $self->{paths} = [bz_locations->{cgi_path}];
    my $version = $+{version};
    my $file    = $+{file};
    $c->stash->{static_file_version} = $version;
    return $self->SUPER::serve($c, $file);
  }
  else {
    return $self->SUPER::serve($c, $rel);
  }
}

1;
