package App::cpm::Resolver::MetaDB;
use strict;
use warnings;

use App::cpm::DistNotation;
use App::cpm::HTTP;
use App::cpm::version;
use CPAN::Meta::YAML;

sub new {
    my ($class, %option) = @_;
    my $uri = $option{uri} || "https://cpanmetadb.plackperl.org/v1.0/";
    my $mirror = $option{mirror} || "https://cpan.metacpan.org/";
    s{/*$}{/} for $uri, $mirror;
    my $http = App::cpm::HTTP->create;
    bless {
        %option,
        http => $http,
        uri => $uri,
        mirror => $mirror,
    }, $class;
}

sub _get {
    my ($self, $uri) = @_;
    my $res;
    for (1..2) {
        $res = $self->{http}->get($uri);
        last if $res->{success} or $res->{status} == 404;
    }
    $res;
}

sub _uniq {
    my %x; grep { !$x{$_ || ""}++ } @_;
}

sub resolve {
    my ($self, $job) = @_;

    if (defined $job->{version_range} and $job->{version_range} =~ /(?:<|!=|==)/) {
        my $uri = "$self->{uri}history/$job->{package}";
        my $res = $self->_get($uri);
        if (!$res->{success}) {
            my $error = "$res->{status} $res->{reason}, $uri";
            $error .= ", $res->{content}" if $res->{status} == 599;
            return { error => $error };
        }

        my @found;
        for my $line ( split /\r?\n/, $res->{content} ) {
            if ($line =~ /^$job->{package}\s+(\S+)\s+(\S+)$/) {
                push @found, {
                    version => $1,
                    version_o => App::cpm::version->parse($1),
                    distfile => $2,
                };
            }
        }

        $found[-1]->{latest} = 1;

        my $match;
        for my $try (sort { $b->{version_o} <=> $a->{version_o} } @found) {
            if ($try->{version_o}->satisfy($job->{version_range})) {
                $match = $try, last;
            }
        }

        if ($match) {
            my $dist = App::cpm::DistNotation->new_from_dist($match->{distfile});
            return {
                source => "cpan",
                package => $job->{package},
                version => $match->{version},
                uri => $dist->cpan_uri($self->{mirror}),
                distfile => $dist->distfile,
            };
        } else {
            return { error => "found versions @{[join ',', _uniq map $_->{version}, @found]}, but they do not satisfy $job->{version_range}, $uri" };
        }
    } else {
        my $uri = "$self->{uri}package/$job->{package}";
        my $res = $self->_get($uri);
        if (!$res->{success}) {
            my $error = "$res->{status} $res->{reason}, $uri";
            $error .= ", $res->{content}" if $res->{status} == 599;
            return { error => $error };
        }

        my $yaml = CPAN::Meta::YAML->read_string($res->{content});
        my $meta = $yaml->[0];
        if (!App::cpm::version->parse($meta->{version})->satisfy($job->{version_range})) {
            return { error => "found version $meta->{version}, but it does not satisfy $job->{version_range}, $uri" };
        }
        my @provides = map {
            my $package = $_;
            my $version = $meta->{provides}{$_};
            $version = undef if $version eq "undef";
            +{ package => $package, version => $version };
        } sort keys %{$meta->{provides}};

        my $dist = App::cpm::DistNotation->new_from_dist($meta->{distfile});
        return {
            source => "cpan",
            distfile => $dist->distfile,
            uri => $dist->cpan_uri($self->{mirror}),
            version  => $meta->{version},
            provides => \@provides,
        };
    }
    return;
}

1;
