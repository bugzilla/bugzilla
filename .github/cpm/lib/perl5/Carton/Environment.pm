package Carton::Environment;
use strict;
use Carton::CPANfile;
use Carton::Snapshot;
use Carton::Error;
use Carton::Tree;
use Path::Tiny;

use Class::Tiny {
    cpanfile => undef,
    snapshot => sub { $_[0]->_build_snapshot },
    install_path => sub { $_[0]->_build_install_path },
    vendor_cache => sub { $_[0]->_build_vendor_cache },
    tree => sub { $_[0]->_build_tree },
};

sub _build_snapshot {
    my $self = shift;
    Carton::Snapshot->new(path => $self->cpanfile . ".snapshot");
}

sub _build_install_path {
    my $self = shift;
    if ($ENV{PERL_CARTON_PATH}) {
        return Path::Tiny->new($ENV{PERL_CARTON_PATH});
    } else {
        return $self->cpanfile->path->parent->child("local");
    }
}

sub _build_vendor_cache {
    my $self = shift;
    Path::Tiny->new($self->install_path->dirname . "/vendor/cache");
}

sub _build_tree {
    my $self = shift;
    Carton::Tree->new(cpanfile => $self->cpanfile, snapshot => $self->snapshot);
}

sub vendor_bin {
    my $self = shift;
    $self->vendor_cache->parent->child('bin');
}

sub build_with {
    my($class, $cpanfile) = @_;

    $cpanfile = Path::Tiny->new($cpanfile)->absolute;
    if ($cpanfile->is_file) {
        return $class->new(cpanfile => Carton::CPANfile->new(path => $cpanfile));
    } else {
        Carton::Error::CPANfileNotFound->throw(error => "Can't locate cpanfile: $cpanfile");
    }
}

sub build {
    my($class, $cpanfile_path, $install_path) = @_;

    my $self = $class->new;

    $cpanfile_path &&= Path::Tiny->new($cpanfile_path)->absolute;

    my $cpanfile = $self->locate_cpanfile($cpanfile_path || $ENV{PERL_CARTON_CPANFILE});
    if ($cpanfile && $cpanfile->is_file) {
        $self->cpanfile( Carton::CPANfile->new(path => $cpanfile) );
    } else {
        Carton::Error::CPANfileNotFound->throw(error => "Can't locate cpanfile: (@{[ $cpanfile_path || 'cpanfile' ]})");
    }

    $self->install_path( Path::Tiny->new($install_path)->absolute ) if $install_path;

    $self;
}

sub locate_cpanfile {
    my($self, $path) = @_;

    if ($path) {
        return Path::Tiny->new($path)->absolute;
    }

    my $current  = Path::Tiny->cwd;
    my $previous = '';

    until ($current eq '/' or $current eq $previous) {
        # TODO support PERL_CARTON_CPANFILE
        my $try = $current->child('cpanfile');
        if ($try->is_file) {
            return $try->absolute;
        }

        ($previous, $current) = ($current, $current->parent);
    }

    return;
}

1;

