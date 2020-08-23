package Carton::CPANfile;
use Path::Tiny ();
use Module::CPANfile;

use overload q{""} => sub { $_[0]->stringify }, fallback => 1;

use subs 'path';

use Class::Tiny {
    path => undef,
    _cpanfile => undef,
    requirements => sub { $_[0]->_build_requirements },
};

sub stringify { shift->path->stringify(@_) }
sub dirname   { shift->path->dirname(@_) }
sub prereqs   { shift->_cpanfile->prereqs(@_) }
sub required_modules { shift->requirements->required_modules(@_) }
sub requirements_for_module { shift->requirements->requirements_for_module(@_) }

sub path {
    my $self = shift;
    if (@_) {
        $self->{path} = Path::Tiny->new($_[0]);
    } else {
        $self->{path};
    }
}

sub load {
    my $self = shift;
    $self->_cpanfile( Module::CPANfile->load($self->path) );
}

sub _build_requirements {
    my $self = shift;
    my $reqs = CPAN::Meta::Requirements->new;
    $reqs->add_requirements($self->prereqs->requirements_for($_, 'requires'))
        for qw( configure build runtime test develop );
    $reqs->clear_requirement('perl');
    $reqs;
}

1;
