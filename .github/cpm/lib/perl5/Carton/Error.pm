package Carton::Error;
use strict;
use overload '""' => sub { $_[0]->error };
use Carp;

sub throw {
    my($class, @args) = @_;
    die $class->new(@args);
}

sub rethrow {
    die $_[0];
}

sub new {
    my($class, %args) = @_;
    bless \%args, $class;
}

sub error {
    $_[0]->{error} || ref $_[0];
}

package Carton::Error::CommandNotFound;
use parent 'Carton::Error';

package Carton::Error::CommandExit;
use parent 'Carton::Error';
sub code { $_[0]->{code} }

package Carton::Error::CPANfileNotFound;
use parent 'Carton::Error';

package Carton::Error::SnapshotParseError;
use parent 'Carton::Error';
sub path { $_[0]->{path} }

package Carton::Error::SnapshotNotFound;
use parent 'Carton::Error';
sub path { $_[0]->{path} }

1;
