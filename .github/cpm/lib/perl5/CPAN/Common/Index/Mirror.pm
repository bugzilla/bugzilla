use 5.008001;
use strict;
use warnings;

package CPAN::Common::Index::Mirror;
# ABSTRACT: Search index via CPAN mirror flatfiles

our $VERSION = '0.010';

use parent 'CPAN::Common::Index';

use Class::Tiny qw/cache mirror/;

use Carp;
use CPAN::DistnameInfo;
use File::Basename ();
use File::Fetch;
use File::Temp 0.19; # newdir
use Search::Dict 1.07;
use Tie::Handle::SkipHeader;
use URI;

our $HAS_IO_UNCOMPRESS_GUNZIP = eval { require IO::Uncompress::Gunzip };

#pod =attr mirror
#pod
#pod URI to a CPAN mirror.  Defaults to C<http://www.cpan.org/>.
#pod
#pod =attr cache
#pod
#pod Path to a local directory to store copies of the source indices.  Defaults to a
#pod temporary directory if not specified.
#pod
#pod =cut

sub BUILD {
    my $self = shift;

    # cache directory needs to exist
    my $cache = $self->cache;
    $cache = File::Temp->newdir
      unless defined $cache;
    if ( !-d $cache ) {
        Carp::croak("Cache directory '$cache' does not exist");
    }
    $self->cache($cache);

    # ensure mirror URL ends in '/'
    my $mirror = $self->mirror;
    $mirror = "http://www.cpan.org/"
      unless defined $mirror;
    $mirror =~ s{/?$}{/};
    $self->mirror($mirror);

    return;
}

my %INDICES = (
    mailrc   => 'authors/01mailrc.txt.gz',
    packages => 'modules/02packages.details.txt.gz',
);

# XXX refactor out from subs below
my %TEST_GENERATORS = (
    regexp_nocase => sub {
        my $arg = shift;
        my $re = ref $arg eq 'Regexp' ? $arg : qr/\A\Q$arg\E\z/i;
        return sub { $_[0] =~ $re };
    },
    regexp => sub {
        my $arg = shift;
        my $re = ref $arg eq 'Regexp' ? $arg : qr/\A\Q$arg\E\z/;
        return sub { $_[0] =~ $re };
    },
    version => sub {
        my $arg = shift;
        my $v   = version->parse($arg);
        return sub {
            eval { version->parse( $_[0] ) == $v };
        };
    },
);

my %QUERY_TYPES = (
    # package search
    package => 'regexp',
    version => 'version',
    dist    => 'regexp',

    # author search
    id       => 'regexp_nocase', # XXX need to add "alias " first
    fullname => 'regexp_nocase',
    email    => 'regexp_nocase',
);

sub cached_package {
    my ($self) = @_;
    my $package = File::Spec->catfile( $self->cache,
        File::Basename::basename( $INDICES{packages} ) );
    $package =~ s/\.gz$//;
    $self->refresh_index unless -r $package;
    return $package;
}

sub cached_mailrc {
    my ($self) = @_;
    my $mailrc =
      File::Spec->catfile( $self->cache, File::Basename::basename( $INDICES{mailrc} ) );
    $mailrc =~ s/\.gz$//;
    $self->refresh_index unless -r $mailrc;
    return $mailrc;
}

sub refresh_index {
    my ($self) = @_;
    for my $file ( values %INDICES ) {
        my $remote = URI->new_abs( $file, $self->mirror );
        $remote =~ s/\.gz$//
          unless $HAS_IO_UNCOMPRESS_GUNZIP;
        my $ff = File::Fetch->new( uri => $remote );
        my $where = $ff->fetch( to => $self->cache )
          or Carp::croak( $ff->error );
        if ($HAS_IO_UNCOMPRESS_GUNZIP) {
            ( my $uncompressed = $where ) =~ s/\.gz$//;
            no warnings 'once';
            IO::Uncompress::Gunzip::gunzip( $where, $uncompressed )
              or Carp::croak "gunzip failed: $IO::Uncompress::Gunzip::GunzipError\n";
        }
    }
    return 1;
}

# epoch secs
sub index_age {
    my ($self) = @_;
    my $package = $self->cached_package;
    return ( -r $package ? ( stat($package) )[9] : 0 ); # mtime if readable
}

sub search_packages {
    my ( $self, $args ) = @_;
    Carp::croak("Argument to search_packages must be hash reference")
      unless ref $args eq 'HASH';

    my $index_path = $self->cached_package;
    die "Can't read $index_path" unless -r $index_path;

    my $fh = IO::Handle->new;
    tie *$fh, 'Tie::Handle::SkipHeader', "<", $index_path
      or die "Can't tie $index_path: $!";

    # Convert scalars or regexps to subs
    my $rules;
    while ( my ( $k, $v ) = each %$args ) {
        $rules->{$k} = _rulify( $k, $v );
    }

    my @found;
    if ( $args->{package} and ref $args->{package} eq '' ) {
        # binary search 02packages on package
        my $pos = look $fh, $args->{package}, { xfrm => \&_xform_package, fold => 1 };
        return if $pos == -1;
        # loop over any case-insensitive matching lines
        LINE: while ( my $line = <$fh> ) {
            last unless $line =~ /\A\Q$args->{package}\E\s+/i;
            push @found, _match_package_line( $line, $rules );
        }
    }
    else {
        # iterate all lines looking for match
        LINE: while ( my $line = <$fh> ) {
            push @found, _match_package_line( $line, $rules );
        }
    }
    return wantarray ? @found : $found[0];
}

sub search_authors {
    my ( $self, $args ) = @_;
    Carp::croak("Argument to search_authors must be hash reference")
      unless ref $args eq 'HASH';

    my $index_path = $self->cached_mailrc;
    die "Can't read $index_path" unless -r $index_path;
    open my $fh, $index_path or die "Can't open $index_path: $!";

    # Convert scalars or regexps to subs
    my $rules;
    while ( my ( $k, $v ) = each %$args ) {
        $rules->{$k} = _rulify( $k, $v );
    }

    my @found;
    if ( $args->{id} and ref $args->{id} eq '' ) {
        # binary search mailrec on package
        my $pos = look $fh, $args->{id}, { xfrm => \&_xform_mailrc, fold => 1 };
        return if $pos == -1;
        my $line = <$fh>;
        push @found, _match_mailrc_line( $line, $rules );
    }
    else {
        # iterate all lines looking for match
        LINE: while ( my $line = <$fh> ) {
            push @found, _match_mailrc_line( $line, $rules );
        }
    }
    return wantarray ? @found : $found[0];
}

sub _rulify {
    my ( $key, $arg ) = @_;
    return $arg if ref($arg) eq 'CODE';
    return $TEST_GENERATORS{ $QUERY_TYPES{$key} }->($arg);
}

sub _xform_package {
    my @fields = split " ", $_[0], 2;
    return $fields[0];
}

sub _xform_mailrc {
    my @fields = split " ", $_[0], 3;
    return $fields[1];
}

sub _match_package_line {
    my ( $line, $rules ) = @_;
    return unless defined $line;
    my ( $mod, $version, $dist, $comment ) = split " ", $line, 4;
    if ( $rules->{package} ) {
        return unless $rules->{package}->($mod);
    }
    if ( $rules->{version} ) {
        return unless $rules->{version}->($version);
    }
    if ( $rules->{dist} ) {
        return unless $rules->{dist}->($dist);
    }
    $dist =~ s{\A./../}{};
    return {
        package => $mod,
        version => $version,
        uri     => "cpan:///distfile/$dist",
    };
}

sub _match_mailrc_line {
    my ( $line, $rules ) = @_;
    return unless defined $line;
    my ( $id,       $address ) = $line =~ m{\Aalias\s+(\S+)\s+"(.*)"};
    my ( $fullname, $email )   = $address =~ m{([^<]+)<([^>]+)>};
    $fullname =~ s/\s*$//;
    if ( $rules->{id} ) {
        return unless $rules->{id}->($id);
    }
    if ( $rules->{fullname} ) {
        return unless $rules->{fullname}->($fullname);
    }
    if ( $rules->{email} ) {
        return unless $rules->{email}->($email);
    }
    return {
        id       => $id,
        fullname => $fullname,
        email    => $email,
    };
}

1;


# vim: ts=4 sts=4 sw=4 et:

__END__

=pod

=encoding UTF-8

=head1 NAME

CPAN::Common::Index::Mirror - Search index via CPAN mirror flatfiles

=head1 VERSION

version 0.010

=head1 SYNOPSIS

  use CPAN::Common::Index::Mirror;

  # default mirror is http://www.cpan.org/
  $index = CPAN::Common::Index::Mirror->new;

  # custom mirror
  $index = CPAN::Common::Index::Mirror->new(
    { mirror => "http://cpan.cpantesters.org" }
  );

=head1 DESCRIPTION

This module implements a CPAN::Common::Index that retrieves and searches
02packages.details.txt and 01mailrc.txt indices.

The default mirror is L<http://www.cpan.org/>.  This is a globally balanced
fast mirror and is a great choice if you don't have a local fast mirror.

=head1 ATTRIBUTES

=head2 mirror

URI to a CPAN mirror.  Defaults to C<http://www.cpan.org/>.

=head2 cache

Path to a local directory to store copies of the source indices.  Defaults to a
temporary directory if not specified.

=for Pod::Coverage attributes validate_attributes search_packages search_authors
cached_package cached_mailrc BUILD

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by David Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
