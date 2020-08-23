use 5.008001;
use strict;
use warnings;

package CPAN::Common::Index::LocalPackage;
# ABSTRACT: Search index via custom local CPAN package flatfile

our $VERSION = '0.010';

use parent 'CPAN::Common::Index::Mirror';

use Class::Tiny qw/source/;

use Carp;
use File::Basename ();
use File::Copy ();
use File::Spec;
use File::stat ();

#pod =attr source (REQUIRED)
#pod
#pod Path to a local file in the form of 02packages.details.txt.  It may
#pod be compressed with a ".gz" suffix or it may be uncompressed.
#pod
#pod =attr cache
#pod
#pod Path to a local directory to store a (possibly uncompressed) copy
#pod of the source index.  Defaults to a temporary directory if not
#pod specified.
#pod
#pod =cut

sub BUILD {
    my $self = shift;

    my $file = $self->source;
    if ( !defined $file ) {
        Carp::croak("'source' parameter must be provided");
    }
    elsif ( !-f $file ) {
        Carp::croak("index file '$file' does not exist");
    }

    return;
}

sub cached_package {
    my ($self) = @_;
    my $package = File::Spec->catfile(
        $self->cache, File::Basename::basename($self->source)
    );
    $package =~ s/\.gz$//;
    $self->refresh_index unless -r $package;
    return $package;
}

sub refresh_index {
    my ($self) = @_;
    my $source = $self->source;
    my $basename = File::Basename::basename($source);
    if ( $source =~ /\.gz$/ ) {
        Carp::croak "can't load gz source files without IO::Uncompress::Gunzip\n"
          unless $CPAN::Common::Index::Mirror::HAS_IO_UNCOMPRESS_GUNZIP;
        ( my $uncompressed = $basename ) =~ s/\.gz$//;
        $uncompressed = File::Spec->catfile( $self->cache, $uncompressed );
        if ( !-f $uncompressed
              or File::stat::stat($source)->mtime > File::stat::stat($uncompressed)->mtime ) {
            no warnings 'once';
            IO::Uncompress::Gunzip::gunzip( map { "$_" } $source, $uncompressed )
              or Carp::croak "gunzip failed: $IO::Uncompress::Gunzip::GunzipError\n";
        }
    }
    else {
        my $dest = File::Spec->catfile( $self->cache, $basename );
        File::Copy::copy($source, $dest)
          if !-e $dest || File::stat::stat($source)->mtime > File::stat::stat($dest)->mtime;
    }
    return 1;
}

sub search_authors { return }; # this package handles packages only

1;


# vim: ts=4 sts=4 sw=4 et:

__END__

=pod

=encoding UTF-8

=head1 NAME

CPAN::Common::Index::LocalPackage - Search index via custom local CPAN package flatfile

=head1 VERSION

version 0.010

=head1 SYNOPSIS

  use CPAN::Common::Index::LocalPackage;

  $index = CPAN::Common::Index::LocalPackage->new(
    { source => "mypackages.details.txt" }
  );

=head1 DESCRIPTION

This module implements a CPAN::Common::Index that searches for packages in a local
index file in the same form as the CPAN 02packages.details.txt file.

There is no support for searching on authors.

=head1 ATTRIBUTES

=head2 source (REQUIRED)

Path to a local file in the form of 02packages.details.txt.  It may
be compressed with a ".gz" suffix or it may be uncompressed.

=head2 cache

Path to a local directory to store a (possibly uncompressed) copy
of the source index.  Defaults to a temporary directory if not
specified.

=for Pod::Coverage attributes validate_attributes search_packages search_authors
cached_package BUILD

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by David Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
