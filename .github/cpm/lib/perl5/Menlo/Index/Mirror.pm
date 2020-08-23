package Menlo::Index::Mirror;
use strict;
use parent qw(CPAN::Common::Index::Mirror);
use Class::Tiny qw(fetcher);

use File::Basename ();
use File::Spec ();
use URI ();

our $HAS_IO_UNCOMPRESS_GUNZIP = eval { require IO::Uncompress::Gunzip };

my %INDICES = (
#    mailrc   => 'authors/01mailrc.txt.gz',
    packages => 'modules/02packages.details.txt.gz',
);

sub refresh_index {
    my $self = shift;
    for my $file ( values %INDICES ) {
        my $remote = URI->new_abs( $file, $self->mirror );
        $remote =~ s/\.gz$//
          unless $HAS_IO_UNCOMPRESS_GUNZIP;
        my $local = File::Spec->catfile( $self->cache, File::Basename::basename($file) );
        $self->fetcher->($remote, $local)
          or Carp::croak( "Cannot fetch $remote to $local");
        if ($HAS_IO_UNCOMPRESS_GUNZIP) {
            ( my $uncompressed = $local ) =~ s/\.gz$//;
            IO::Uncompress::Gunzip::gunzip( $local, $uncompressed )
              or Carp::croak "gunzip failed: $IO::Uncompress::Gunzip::GunzipError\n";
        }
    }
}

1;
