use 5.008001;
use strict;
use warnings;

package CPAN::Common::Index::MetaDB;
# ABSTRACT: Search index via CPAN MetaDB

our $VERSION = '0.010';

use parent 'CPAN::Common::Index';

use Class::Tiny qw/uri/;

use Carp;
use CPAN::Meta::YAML;
use HTTP::Tiny;

#pod =attr uri
#pod
#pod A URI for the endpoint of a CPAN MetaDB server. The
#pod default is L<http://cpanmetadb.plackperl.org/v1.0/>.
#pod
#pod =cut

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

    # only support direct package query
    return
      unless keys %$args == 1 && exists $args->{package} && ref $args->{package} eq '';

    my $mod = $args->{package};
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

    return;
}

sub index_age { return time };    # pretend always current

sub search_authors { return };    # not supported

1;


# vim: ts=4 sts=4 sw=4 et:

__END__

=pod

=encoding UTF-8

=head1 NAME

CPAN::Common::Index::MetaDB - Search index via CPAN MetaDB

=head1 VERSION

version 0.010

=head1 SYNOPSIS

  use CPAN::Common::Index::MetaDB;

  $index = CPAN::Common::Index::MetaDB->new;

=head1 DESCRIPTION

This module implements a CPAN::Common::Index that searches for packages against
the same CPAN MetaDB API used by L<cpanminus>.

There is no support for advanced package queries or searching authors.  It just
takes a package name and returns the corresponding version and distribution.

=head1 ATTRIBUTES

=head2 uri

A URI for the endpoint of a CPAN MetaDB server. The
default is L<http://cpanmetadb.plackperl.org/v1.0/>.

=for Pod::Coverage attributes validate_attributes search_packages search_authors BUILD

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by David Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
