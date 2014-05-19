# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::ReviewBoard::Resource;

use 5.10.1;
use strict;
use warnings;

use URI;
use Carp qw(croak confess);
use Scalar::Util qw(blessed);

sub new {
    my ($class, %params) = @_;

    croak "->new() is a class method" if blessed($class);
    return bless(\%params, $class);
}

sub client { $_[0]->{client} }

sub path { confess 'Unimplemented'; }

sub uri {
    my ($self, @path) = @_;

    my $uri = URI->new($self->client->base_uri);
    $uri->path(join('/', $self->path, @path) . '/');

    return $uri;
}

1;
