package Carton::Snapshot;
use strict;
use Config;
use Carton::Dist;
use Carton::Dist::Core;
use Carton::Error;
use Carton::Package;
use Carton::Index;
use Carton::Util;
use Carton::Snapshot::Emitter;
use Carton::Snapshot::Parser;
use CPAN::Meta;
use CPAN::Meta::Requirements;
use File::Find ();
use Try::Tiny;
use Path::Tiny ();
use Module::CoreList;

use constant CARTON_SNAPSHOT_VERSION => '1.0';

use subs 'path';
use Class::Tiny {
    path => undef,
    version => sub { CARTON_SNAPSHOT_VERSION },
    loaded => undef,
    _distributions => sub { +[] },
};

sub BUILD {
    my $self = shift;
    $self->path( $self->{path} );
}    

sub path {
    my $self = shift;
    if (@_) {
        $self->{path} = Path::Tiny->new($_[0]);
    } else {
        $self->{path};
    }
}

sub load_if_exists {
    my $self = shift;
    $self->load if $self->path->is_file;
}

sub load {
    my $self = shift;

    return 1 if $self->loaded;

    if ($self->path->is_file) {
        my $parser = Carton::Snapshot::Parser->new;
        $parser->parse($self->path->slurp_utf8, $self);
        $self->loaded(1);

        return 1;
    } else {
        Carton::Error::SnapshotNotFound->throw(
            error => "Can't find cpanfile.snapshot: Run `carton install` to build the snapshot file.",
            path => $self->path,
        );
    }
}

sub save {
    my $self = shift;
    $self->path->spew_utf8( Carton::Snapshot::Emitter->new->emit($self) );
}

sub find {
    my($self, $module) = @_;
    (grep $_->provides_module($module), $self->distributions)[0];
}

sub find_or_core {
    my($self, $module) = @_;
    $self->find($module) || $self->find_in_core($module);
}

sub find_in_core {
    my($self, $module) = @_;

    if (exists $Module::CoreList::version{$]}{$module}) {
        my $version = $Module::CoreList::version{$]}{$module}; # maybe undef
        return Carton::Dist::Core->new(name => $module, module_version => $version);
    }

    return;
}

sub index {
    my $self = shift;

    my $index = Carton::Index->new;
    for my $package ($self->packages) {
        $index->add_package($package);
    }

    return $index;
}

sub distributions {
    @{$_[0]->_distributions};
}

sub add_distribution {
    my($self, $dist) = @_;
    push @{$self->_distributions}, $dist;
}

sub packages {
    my $self = shift;

    my @packages;
    for my $dist ($self->distributions) {
        while (my($package, $provides) = each %{$dist->provides}) {
            # TODO what if duplicates?
            push @packages, Carton::Package->new($package, $provides->{version}, $dist->pathname);
        }
    }

    return @packages;
}

sub write_index {
    my($self, $file) = @_;

    open my $fh, ">", $file or die $!;
    $self->index->write($fh);
}

sub find_installs {
    my($self, $path, $reqs) = @_;

    my $libdir = "$path/lib/perl5/$Config{archname}/.meta";
    return {} unless -e $libdir;

    my @installs;
    my $wanted = sub {
        if ($_ eq 'install.json') {
            push @installs, [ $File::Find::name, "$File::Find::dir/MYMETA.json" ];
        }
    };
    File::Find::find($wanted, $libdir);

    my %installs;

    my $accepts = sub {
        my $module = shift;

        return 0 unless $reqs->accepts_module($module->{name}, $module->{provides}{$module->{name}}{version});

        if (my $exist = $installs{$module->{name}}) {
            my $old_ver = version::->new($exist->{provides}{$module->{name}}{version});
            my $new_ver = version::->new($module->{provides}{$module->{name}}{version});
            return $new_ver >= $old_ver;
        } else {
            return 1;
        }
    };

    for my $file (@installs) {
        my $module = Carton::Util::load_json($file->[0]);
        my $prereqs = -f $file->[1] ? CPAN::Meta->load_file($file->[1])->effective_prereqs : CPAN::Meta::Prereqs->new;

        my $reqs = CPAN::Meta::Requirements->new;
        $reqs->add_requirements($prereqs->requirements_for($_, 'requires'))
          for qw( configure build runtime );

        if ($accepts->($module)) {
            $installs{$module->{name}} = Carton::Dist->new(
                name => $module->{dist},
                pathname => $module->{pathname},
                provides => $module->{provides},
                version => $module->{version},
                requirements => $reqs,
            );
        }
    }

    my @new_dists;
    for my $module (sort keys %installs) {
        push @new_dists, $installs{$module};
    }

    $self->_distributions(\@new_dists);
}

1;
