# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::ReviewBoard::Client;

use 5.10.1;
use strict;
use warnings;

use Carp qw(croak);
use LWP::UserAgent;
use Scalar::Util qw(blessed);
use URI;

use Bugzilla::Extension::Push::Connector::ReviewBoard::ReviewRequest;

sub new {
    my ($class, %params) = @_;

    croak "->new() is a class method" if blessed($class);
    return bless(\%params, $class);
}

sub username { $_[0]->{username} }
sub password { $_[0]->{password} }
sub base_uri { $_[0]->{base_uri} }
sub realm    { $_[0]->{realm} // 'Web API' }
sub proxy    { $_[0]->{proxy} }

sub _netloc {
    my $self = shift;

    my $uri  = URI->new($self->base_uri);
    return $uri->host . ':' . $uri->port;
}

sub useragent {
    my $self = shift;

    unless ($self->{useragent}) {
        my $ua = LWP::UserAgent->new(agent => Bugzilla->params->{urlbase});
        $ua->credentials(
            $self->_netloc,
            $self->realm,
            $self->username,
            $self->password,
        );
        $ua->proxy('https', $self->proxy) if $self->proxy;
        $ua->timeout(10);

        $self->{useragent} = $ua;
    }

    return $self->{useragent};
}

sub review_request {
    my $self = shift;

    return Bugzilla::Extension::Push::Connector::ReviewBoard::ReviewRequest->new(client => $self, @_);
}

1;
