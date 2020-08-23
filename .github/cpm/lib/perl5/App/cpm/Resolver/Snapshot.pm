package App::cpm::Resolver::Snapshot;
use strict;
use warnings;

use App::cpm::DistNotation;
use App::cpm::version;
use Carton::Snapshot;

sub new {
    my ($class, %option) = @_;
    my $snapshot = Carton::Snapshot->new(path => $option{path} || "cpanfile.snapshot");
    $snapshot->load;
    my $mirror = $option{mirror} || "https://cpan.metacpan.org/";
    $mirror =~ s{/*$}{/};
    bless {
        %option,
        mirror => $mirror,
        snapshot => $snapshot
    }, $class;
}

sub snapshot { shift->{snapshot} }

sub resolve {
    my ($self, $job) = @_;
    my $package = $job->{package};
    my $found = $self->snapshot->find($package);
    if (!$found) {
        return { error => "not found, @{[$self->snapshot->path]}" };
    }

    my $version = $found->version_for($package);
    if (my $version_range = $job->{version_range}) {
        if (!App::cpm::version->parse($version)->satisfy($version_range)) {
            return { error => "found version $version, but it does not satisfy $version_range, @{[$self->snapshot->path]}" };
        }
    }

    my @provides = map {
        my $package = $_;
        my $version = $found->provides->{$_}{version};
        +{ package => $package, version => $version };
    } sort keys %{$found->provides};

    my $dist = App::cpm::DistNotation->new_from_dist($found->distfile);
    return {
        source => "cpan",
        distfile => $dist->distfile,
        uri => $dist->cpan_uri($self->{mirror}),
        version  => $version || 0,
        provides => \@provides,
    };
}

1;
