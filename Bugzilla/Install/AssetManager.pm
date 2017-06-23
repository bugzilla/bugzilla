# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Install::AssetManager;

use 5.10.1;
use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;
use Type::Utils;
use Types::Standard qw(Bool Str ArrayRef);

use Digest::SHA ();
use File::Copy qw(cp);
use File::Find qw(find);
use File::Basename qw(dirname);
use File::Spec;
use JSON::XS ();
use MIME::Base64 qw(encode_base64);
use File::Slurp;
use List::MoreUtils qw(any all);
use Carp;

use Bugzilla::Constants qw(bz_locations);

our $VERSION = 1;

my $SHA_VERSION = '224';

my $ABSOLUTE_DIR = declare as Str, where { File::Spec->file_name_is_absolute($_) && -d $_ }
message {"must be an absolute path to a directory"};

has 'base_dir'  => ( is => 'lazy', isa => $ABSOLUTE_DIR );
has 'asset_dir' => ( is => 'lazy', isa => $ABSOLUTE_DIR );
has 'source_dirs' => ( is => 'lazy' );
has 'state'       => ( is => 'lazy' );
has 'state_file'  => ( is => 'lazy' );
has 'json'        => ( is => 'lazy' );

sub asset_file {
    my ( $self, $file, $relative_to ) = @_;
    $relative_to //= $self->base_dir;
    my $asset_file = $self->state->{asset_map}->{$file}
        or return $file;

    return File::Spec->abs2rel( File::Spec->catfile( $self->asset_dir, $asset_file ), $relative_to );
}

sub asset_files {
    my ( $self, @files ) = @_;

    return \@files;
}

sub asset_sri {
    my ( $self, $asset_file ) = @_;
    my ($hex) = $asset_file =~ m!([[:xdigit:]]+)\.\w+$!;
    my $data = pack "H*", $hex;
    return "sha$SHA_VERSION-" . encode_base64( $data, "" );
}

sub compile_file {
    my ( $self, $file ) = @_;
    return unless -f $file;
    my $base_dir  = $self->base_dir;
    my $asset_dir = $self->asset_dir;
    my $asset_map = $self->state->{asset_map};

    my $key = File::Spec->abs2rel( $file, $base_dir );
    return if $asset_map->{$key};

    if ( $file =~ /\.(jpe?g|png|gif|ico|woff|js)$/i ) {
        my $ext        = $1;
        my $digest     = $self->_digest_file($file) or die "invalid digest for $file";
        my $asset_file = File::Spec->catfile( $asset_dir, "$digest.$ext" );
        cp( $file, $asset_file ) or die "failed to copy $file to $asset_file: $!";
        if ( $digest eq $self->_digest_file($asset_file) ) {
            $asset_map->{$key} = File::Spec->abs2rel( $asset_file, $asset_dir );
        }
        else {
            die "failed to write $asset_file";
        }
    }
    elsif ( $file =~ /\.css$/ ) {
        my $content = read_file($file);

        $content =~ s{(?<!=)url\(([^\)]+)\)}{$self->_css_url_rewrite($1, $file)}eig;
        my $digest = $self->_digest_string($content);
        my $asset_file = File::Spec->catfile( $asset_dir, "$digest.css" );
        write_file( $asset_file, $content ) or die "failed to write $asset_file: $!";
        if ( $digest eq $self->_digest_file($asset_file) ) {
            $asset_map->{$key} = File::Spec->abs2rel( $asset_file, $asset_dir );
        }
        else {
            die "failed to write $asset_file";
        }
    }
}

sub compile_all {
    my ($self) = @_;
    my $asset_map = $self->state->{asset_map} = {};

    my $wanted = sub {
        $self->compile_file($File::Find::name);
    };

    find( { wanted => $wanted, no_chdir => 1 }, @{ $self->source_dirs } );

    $self->_save_state();
}

sub _css_url_rewrite {
    my ( $self, $url, $file ) = @_;
    my $dir = dirname($file);

    # rewrite relative urls as the unified stylesheet lives in a different
    # directory from the source
    $url =~ s/(^['"]|['"]$)//g;
    if ( $url =~ m!^(/|data:)! ) {
        return 'url(' . $url . ')';
    }
    else {
        my $url_file = File::Spec->rel2abs( $url, $dir );
        my $ref_file = File::Spec->abs2rel( $url_file, $self->base_dir );
        $self->compile_file($url_file);
        return sprintf( "url(%s)", $self->asset_file( $ref_file, $self->asset_dir ) );
    }
}

sub _new_digest { Digest::SHA->new($SHA_VERSION) }

sub _digest_file {
    my ( $self, $file ) = @_;
    my $digest = $self->_new_digest;
    $digest->addfile( $file, "b" );
    return $digest->hexdigest;
}

sub _digest_string {
    my ( $self, $string ) = @_;
    my $digest = $self->_new_digest;
    $digest->add($string);
    return $digest->hexdigest;
}

sub _build_base_dir {
    Cwd::realpath( File::Spec->rel2abs( bz_locations->{cgi_path} ) );
}

sub _build_asset_dir {
    my ($self) = @_;
    my $dir
        = Cwd::realpath( File::Spec->rel2abs( bz_locations->{assetsdir} ) );

    if ( $dir && -d $dir ) {
        my $version_dir = File::Spec->catdir( $dir, "v" . $self->VERSION );
        unless ( -d $version_dir ) {
            mkdir $version_dir or die "mkdir $version_dir failed: $!";
        }
        return $version_dir;
    }
    else {
        return $dir;
    }
}

sub _build_source_dirs {
    my ($self)  = @_;
    my $base    = $self->base_dir;
    my $ext_dir = "$base/extensions";
    opendir my $ext_dir_handle, $ext_dir or die "unable to open $ext_dir: $!";
    my @dirs = grep { -d $_ } map {"$ext_dir/$_/web"} grep { !/^\.\.?$/ } readdir $ext_dir_handle;
    closedir $ext_dir_handle;

    return [ "$base/skins", "$base/js", grep { -d $_ } @dirs ];
}

sub _build_state_file {
    my ($self) = @_;
    return $self->asset_dir . "/state.json";
}

sub _build_state {
    my ($self) = @_;
    my $state;
    if ( open my $fh, '<:bytes', $self->state_file ) {
        local $/ = undef;
        my $json = <$fh>;
        close $fh;
        $state = $self->json->decode($json);
    }
    else {
        $state = {};
    }

    $state->{asset_map} //= {};

    return $state;
}

sub _build_json { JSON::XS->new->canonical->utf8 }

sub _save_state {
    my ($self) = @_;
    open my $fh, '>:bytes', $self->state_file
        or die "unable to write state file: $!";
    print $fh $self->json->encode( $self->state );
    close $fh;
}

1;
