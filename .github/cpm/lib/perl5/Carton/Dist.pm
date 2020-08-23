package Carton::Dist;
use strict;
use Class::Tiny {
    name => undef,
    pathname => undef,
    provides => sub { +{} },
    requirements => sub { $_[0]->_build_requirements },
};

use CPAN::Meta;

sub add_string_requirement  { shift->requirements->add_string_requirement(@_) }
sub required_modules        { shift->requirements->required_modules(@_) }
sub requirements_for_module { shift->requirements->requirements_for_module(@_) }

sub is_core { 0 }

sub distfile {
    my $self = shift;
    $self->pathname;
}

sub _build_requirements {
    CPAN::Meta::Requirements->new;
}

sub provides_module {
    my($self, $module) = @_;
    exists $self->provides->{$module};
}

sub version_for {
    my($self, $module) = @_;
    $self->provides->{$module}{version};
}

1;
