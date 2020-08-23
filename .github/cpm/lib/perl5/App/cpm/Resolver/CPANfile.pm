package App::cpm::Resolver::CPANfile;
use strict;
use warnings;

use App::cpm::DistNotation;
use Module::CPANfile;

sub new {
    my ($class, %args) = @_;

    my $cpanfile = $args{cpanfile} || Module::CPANfile->load($args{path});
    my $mirror = $args{mirror} || 'https://cpan.metacpan.org/';
    $mirror =~ s{/*$}{/};
    my $self = bless {
        %args,
        cpanfile => $cpanfile,
        mirror => $mirror,
    }, $class;
    $self->_load;
    $self;
}

sub _load {
    my $self = shift;

    my $cpanfile = $self->{cpanfile};
    my $specs = $cpanfile->prereq_specs;
    my %package;
    for my $phase (keys %$specs) {
        for my $type (keys %{$specs->{$phase}}) {
            $package{$_}++ for keys %{$specs->{$phase}{$type}};
        }
    }

    my %resolve;
    for my $package (keys %package) {
        my $option = $cpanfile->options_for_module($package);
        next if !$option;

        my $uri;
        if ($uri = $option->{git}) {
            $resolve{$package} = {
                source => 'git',
                uri => $uri,
                ref => $option->{ref},
                provides => [{package => $package}],
            };
        } elsif ($uri = $option->{dist}) {
            my $dist = App::cpm::DistNotation->new_from_dist($uri);
            die "Unsupported dist '$uri' found in cpanfile\n" if !$dist;
            my $cpan_uri = $dist->cpan_uri($option->{mirror} || $self->{mirror});
            $resolve{$package} = {
                source => 'cpan',
                uri => $cpan_uri,
                distfile => $dist->distfile,
                provides => [{package => $package}],
            };
        } elsif ($uri = $option->{url}) {
            die "Unsupported url '$uri' found in cpanfile\n" if $uri !~ m{^(?:https?|file)://};
            my $dist = App::cpm::DistNotation->new_from_uri($uri);
            my $source = $dist ? 'cpan' : $uri =~ m{^file://} ? 'local' : 'http';
            $resolve{$package} = {
                source => $source,
                uri => $dist ? $dist->cpan_uri : $uri,
                ($dist ? (distfile => $dist->distfile) : ()),
                provides => [{package => $package}],
            };
        }
    }
    $self->{_resolve} = \%resolve;

}

sub resolve {
    my ($self, $job) = @_;
    my $found = $self->{_resolve}{$job->{package}};
    if (!$found) {
        return { error => "not found" };
    }
    $found; # TODO handle version
}

1;
