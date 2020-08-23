package Carton::Dependency;
use strict;
use Class::Tiny {
    module => undef,
    requirement => undef,
    dist => undef,
};

sub requirements { shift->dist->requirements(@_) }

sub distname {
    my $self = shift;
    $self->dist->name;
}

sub version {
    my $self = shift;
    $self->dist->version_for($self->module);
}

1;
