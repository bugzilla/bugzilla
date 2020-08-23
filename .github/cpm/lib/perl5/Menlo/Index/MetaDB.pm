use 5.008001;
use strict;
use warnings;

package Menlo::Index::MetaDB;
# ABSTRACT: Search index via CPAN MetaDB

our $VERSION = "1.9019";

use parent 'CPAN::Common::Index';

use Class::Tiny qw/uri/;

use Carp;
use CPAN::Meta::YAML;
use CPAN::Meta::Requirements;
use HTTP::Tiny;

sub BUILD {
    my $self = shift;
    my $uri  = $self->uri;
    $uri = "http://cpanmetadb.plackperl.org/v1.0/"
      unless defined $uri;
    # ensure URI ends in '/'
    $uri =~ s{/?$}{/};
    $self->uri($uri);
    return;
}

sub search_packages {
    my ( $self, $args ) = @_;
    Carp::croak("Argument to search_packages must be hash reference")
      unless ref $args eq 'HASH';

    return
      unless exists $args->{package} && ref $args->{package} eq '';

    my $mod = $args->{package};

    if ($args->{version} || $args->{version_range}) {
        my $res = HTTP::Tiny->new->get( $self->uri . "history/$mod" );
        return unless $res->{success};

        my $range = defined $args->{version} ? "== $args->{version}" : $args->{version_range};
        my $reqs = CPAN::Meta::Requirements->from_string_hash({ $mod => $range });

        my @found;
        for my $line ( split /\r?\n/, $res->{content} ) {
            if ($line =~ /^$mod\s+(\S+)\s+(\S+)$/) {
                push @found, {
                    version => $1,
                    version_o => version::->parse($1),
                    distfile => $2,
                };
            }
        }

        return unless @found;
        $found[-1]->{latest} = 1;

        my $match;
        for my $try (sort { $b->{version_o} <=> $a->{version_o} } @found) {
            if ($reqs->accepts_module($mod => $try->{version_o})) {
                $match = $try, last;
            }
        }

        if ($match) {
            my $file = $match->{distfile};
            $file =~ s{^./../}{}; # strip leading
            return {
                package => $mod,
                version => $match->{version},
                uri     => "cpan:///distfile/$file",
                ($match->{latest} ? () :
                   (download_uri => "http://backpan.perl.org/authors/id/$match->{distfile}")),
            };
        }
    } else {
        my $res = HTTP::Tiny->new->get( $self->uri . "package/$mod" );
        return unless $res->{success};

        if ( my $yaml = CPAN::Meta::YAML->read_string( $res->{content} ) ) {
            my $meta = $yaml->[0];
            if ( $meta && $meta->{distfile} ) {
                my $file = $meta->{distfile};
                $file =~ s{^./../}{}; # strip leading
                return {
                    package => $mod,
                    version => $meta->{version},
                    uri     => "cpan:///distfile/$file",
                };
            }
        }
    }

    return;
}

sub index_age { return time };    # pretend always current

sub search_authors { return };    # not supported

1;

=for Pod::Coverage attributes validate_attributes search_packages search_authors BUILD

=head1 SYNOPSIS

  use CPAN::Common::Index::MetaDB;

  $index = CPAN::Common::Index::MetaDB->new;

  $index->search_packages({ package => "Moose" });
  $index->search_packages({ package => "Moose", version_range => ">= 2.0" });

=head1 DESCRIPTION

This module implements a CPAN::Common::Index that searches for packages against
the same CPAN MetaDB API used by L<cpanminus>.

There is no support for advanced package queries or searching authors.  It just
takes a package name and returns the corresponding version and distribution.

=cut

# vim: ts=4 sts=4 sw=4 et:
