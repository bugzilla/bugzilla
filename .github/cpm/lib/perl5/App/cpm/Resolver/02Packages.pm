package App::cpm::Resolver::02Packages;
use strict;
use warnings;

use App::cpm::DistNotation;
use App::cpm::version;
use Cwd ();
use File::Path ();

{
    package
        App::cpm::Resolver::02Packages::Impl;
    use parent 'CPAN::Common::Index::Mirror';
    use App::cpm::HTTP;
    use Class::Tiny qw(path);
    use File::Basename ();
    use File::Copy ();
    use File::Spec;

    our $HAS_IO_UNCOMPRESS_GUNZIP = eval { require IO::Uncompress::Gunzip };

    sub BUILD {
        my $self = shift;
        if ($self->path =~ /\.gz$/ and !$HAS_IO_UNCOMPRESS_GUNZIP) {
            die "Can't load gz index file without IO::Uncompress::Gunzip";
        }
        return;
    }

    sub cached_package { shift->{cached_package} }

    sub refresh_index {
        my $self = shift;
        my $path = $self->path;
        my $dest = File::Spec->catfile($self->cache, File::Basename::basename($path));
        if ($path =~ m{^https?://}) {
            my $res = App::cpm::HTTP->create->mirror($path => $dest);
            die "$res->{status} $res->{reason}, $path\n" unless $res->{success};
        } else {
            $path =~ s{^file://}{};
            die "$path: No such file.\n" unless -f $path;
            if (!-f $dest or (stat $dest)[9] <= (stat $path)[9]) {
                File::Copy::copy($path, $dest) or die "Copy $path $dest: $!\n";
                my $mtime = (stat $path)[9];
                utime $mtime, $mtime, $dest;
            }
        }

        if ($dest =~ /\.gz$/) {
            ( my $uncompressed = File::Basename::basename($dest) ) =~ s/\.gz$//;
            $uncompressed = File::Spec->catfile( $self->cache, $uncompressed );
            if ( !-f $uncompressed or (stat $uncompressed)[9] <= (stat $dest)[9] ) {
                no warnings 'once';
                IO::Uncompress::Gunzip::gunzip($dest, $uncompressed)
                    or die "Gunzip $dest: $IO::Uncompress::Gunzip::GunzipError";
            }
            $self->{cached_package} = $uncompressed;
        } else {
            $self->{cached_package} = $dest;
        }
    }
}

sub new {
    my ($class, %option) = @_;
    my $cache_base = $option{cache} or die "cache option is required\n";
    my $mirror = $option{mirror} or die "mirror option is required\n";
    $mirror =~ s{/*$}{/};

    my ($path, $cache);
    if ($option{path}) {
        $path = $option{path};
    } else {
        $path = "${mirror}modules/02packages.details.txt.gz";
        $cache = $class->cache_for($mirror, $cache_base);
    }

    my $impl = App::cpm::Resolver::02Packages::Impl->new(
        path => $path, $cache ? (cache => $cache) : (),
    );
    $impl->refresh_index; # refresh_index first
    bless { mirror => $mirror, impl => $impl }, $class;
}

sub cache_for {
    my ($class, $mirror, $cache) = @_;
    if ($mirror !~ m{^https?://}) {
        $mirror =~ s{^file://}{};
        $mirror = Cwd::abs_path($mirror);
        $mirror =~ s{^/}{};
    }
    $mirror =~ s{/$}{};
    $mirror =~ s/[^\w\.\-]+/%/g;
    my $dir = "$cache/$mirror";
    File::Path::mkpath([ $dir ], 0, 0777);
    return $dir;
}

sub cached_package { shift->{impl}->cached_package }

sub resolve {
    my ($self, $job) = @_;
    my $result = $self->{impl}->search_packages({package => $job->{package}});
    if (!$result) {
        return { error => "not found, @{[$self->cached_package]}" };
    }

    if (my $version_range = $job->{version_range}) {
        my $version = $result->{version};
        if (!App::cpm::version->parse($version)->satisfy($version_range)) {
            return { error => "found version $version, but it does not satisfy $version_range, @{[$self->cached_package]}" };
        }
    }
    my $uri = $result->{uri};
    $uri =~ s{^cpan:///distfile/}{};
    my $dist = App::cpm::DistNotation->new_from_dist($uri);
    return +{
        source => "cpan", # XXX
        distfile => $dist->distfile,
        uri => $dist->cpan_uri($self->{mirror}),
        version => $result->{version} || 0,
        package => $result->{package},
    };
}

1;
