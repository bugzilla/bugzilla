package Carton::Package;
use strict;
use Class::Tiny qw( name version pathname );

sub BUILDARGS {
    my($class, @args) = @_;
    return { name => $args[0], version => $args[1], pathname => $args[2] };
}

sub version_format {
    my $self = shift;
    defined $self->version ? $self->version : 'undef';
}

1;


