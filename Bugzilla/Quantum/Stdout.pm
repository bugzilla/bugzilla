# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::Stdout;
use 5.10.1;
use Moo;

use Bugzilla::Logging;
use Encode;
use English qw(-no_match_vars);

has 'controller' => (
    is       => 'ro',
    required => 1,
);

has '_encoding' => (
    is      => 'rw',
    default => '',
);

sub TIEHANDLE {    ## no critic (unpack)
    my $class = shift;

    return $class->new(@_);
}

sub PRINTF {       ## no critic (unpack)
    my $self = shift;
    $self->PRINT( sprintf @_ );
}

sub PRINT {        ## no critic (unpack)
    my $self  = shift;
    my $c     = $self->controller;
    my $bytes = join '', @_;
    return unless $bytes;
    if ( $self->_encoding ) {
        $bytes = encode( $self->_encoding, $bytes );
    }
    $c->write($bytes . ( $OUTPUT_RECORD_SEPARATOR // '' ) );
}

sub BINMODE {
    my ( $self, $mode ) = @_;
    if ($mode) {
        if ( $mode eq ':bytes' or $mode eq ':raw' ) {
            $self->_encoding('');
        }
        elsif ( $mode eq ':utf8' ) {
            $self->_encoding('utf8');
        }
    }
}

1;
