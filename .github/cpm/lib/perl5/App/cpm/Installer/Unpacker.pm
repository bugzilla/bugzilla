package App::cpm::Installer::Unpacker;

# Based on https://github.com/miyagawa/cpanminus/blob/7b574ede70cebce3709743ec1727f90d745e8580/Menlo-Legacy/lib/Menlo/CLI/Compat.pm#L2756-L2891
use strict;
use warnings;

use File::Basename ();
use File::Temp ();
use File::Which ();
use IPC::Run3 ();

sub run3 {
    my ($cmd, $outfile) = @_;
    my $out;
    IPC::Run3::run3 $cmd, \undef, ($outfile ? $outfile : \$out), \my $err;
    return ($?, $out, $err);
}

sub new {
    my ($class, %argv) = @_;
    my $self = bless \%argv, $class;
    $self->_init_untar;
    $self->_init_unzip;
    $self;
}

sub unpack {
    my ($self, $file) = @_;
    my $method = $file =~ /\.zip$/ ? $self->{method}{unzip} : $self->{method}{untar};
    $self->$method($file);
}

sub describe {
    my $self = shift;
    +{
        map { ($_, $self->{$_}) }
        grep $self->{$_},
        qw(tar gzip bzip2 Archive::Tar unzip Archive::Zip),
    };
}

sub _init_untar {
    my $self = shift;

    my $tar = $self->{tar} = File::Which::which('gtar') || File::Which::which("tar");
    if ($tar) {
        my ($exit, $out, $err) = run3 [$tar, '--version'];
        $self->{tar_kind} = $out =~ /bsdtar/ ? "bsd" : "gnu";
        $self->{tar_bad} = 1 if $out =~ /GNU.*1\.13/i || $^O eq 'MSWin32' || $^O eq 'solaris' || $^O eq 'hpux';
    }

    if ($tar and !$self->{tar_bad}) {
        $self->{method}{untar} = *_untar;
        return if !$self->{_init_all};
    }

    my $gzip  = $self->{gzip} = File::Which::which("gzip");
    my $bzip2 = $self->{bzip2} = File::Which::which("bzip2");

    if ($tar && $gzip && $bzip2) {
        $self->{method}{untar} = *_untar_bad;
        return if !$self->{_init_all};
    }

    if (eval { require Archive::Tar }) {
        $self->{"Archive::Tar"} = Archive::Tar->VERSION;
        $self->{method}{untar} = *_untar_module;
        return if !$self->{_init_all};
    }

    return if $self->{_init_all};
    $self->{method}{untar} = sub { die "There is no backend for untar" };
}

sub _init_unzip {
    my $self = shift;

    my $unzip = $self->{unzip} = File::Which::which("unzip");
    if ($unzip) {
        $self->{method}{unzip} = *_unzip;
        return if !$self->{_init_all};
    }

    if (eval { require Archive::Zip }) {
        $self->{"Archive::Zip"} = Archive::Zip->VERSION;
        $self->{method}{unzip} = *_unzip_module;
        return if !$self->{_init_all};
    }

    return if $self->{_init_all};
    $self->{method}{unzip} = sub { die "There is no backend for unzip" };
}

sub _untar {
    my ($self, $file) = @_;
    my $wantarray = wantarray;

    my ($exit, $out, $err);
    {
        my $ar = $file =~ /\.bz2$/ ? 'j' : 'z';
        ($exit, $out, $err) = run3 [$self->{tar}, "${ar}tf", $file];
        last if $exit != 0;
        my $root = $self->_find_tarroot(split /\r?\n/, $out);
        ($exit, $out, $err) = run3 [$self->{tar}, "${ar}xf", $file, "-o"];
        return $root if $exit == 0 and -d $root;
    }
    return if !$wantarray;
    return (undef, $err || $out);
}

sub _untar_bad {
    my ($self, $file) = @_;
    my $wantarray = wantarray;
    my ($exit, $out, $err);
    {
        my $ar = $file =~ /\.bz2$/ ? $self->{bzip2} : $self->{gzip};
        my $temp = File::Temp->new(SUFFIX => '.tar', EXLOCK => 0);
        ($exit, $out, $err) = run3 [$ar, "-dc", $file], $temp->filename;
        last if $exit != 0;

        # XXX /usr/bin/tar: Cannot connect to C: resolve failed
        my @opt = $^O eq 'MSWin32' && $self->{tar_kind} ne "bsd" ? ('--force-local') : ();
        ($exit, $out, $err) = run3 [$self->{tar}, @opt, "-tf", $temp->filename];
        last if $exit != 0 || !$out;
        my $root = $self->_find_tarroot(split /\r?\n/, $out);
        ($exit, $out, $err) = run3 [$self->{tar}, @opt, "-xf", $temp->filename, "-o"];
        return $root if $exit == 0 and -d $root;
    }
    return if !$wantarray;
    return (undef, $err || $out);
}

sub _untar_module {
    my ($self, $file) = @_;
    my $wantarray = wantarray;
    no warnings 'once';
    local $Archive::Tar::WARN = 0;
    my $t = Archive::Tar->new;
    {
        my $ok = $t->read($file);
        last if !$ok;
        my $root = $self->_find_tarroot($t->list_files);
        my @file = $t->extract;
        return $root if @file and -d $root;
    }
    return if !$wantarray;
    return (undef, $t->error);
}

sub _find_tarroot {
    my ($self, $root, @others) = @_;
    FILE: {
        chomp $root;
        $root =~ s!^\./!!;
        $root =~ s{^(.+?)/.*$}{$1};
        if (!length $root) { # archive had ./ as the first entry, so try again
            $root = shift @others;
            redo FILE if $root;
        }
    }
    $root;
}

sub _unzip {
    my ($self, $file) = @_;
    my $wantarray = wantarray;

    my ($exit, $out, $err);
    {
        ($exit, $out, $err) = run3 [$self->{unzip}, '-t', $file];
        last if $exit != 0;
        my $root = $self->_find_ziproot(split /\r?\n/, $out);
        ($exit, $out, $err) = run3 [$self->{unzip}, '-q', $file];
        return $root if $exit == 0 and -d $root;
    }
    return if !$wantarray;
    return (undef, $err || $out);
}

sub _unzip_module {
    my ($self, $file) = @_;
    my $wantarray = wantarray;

    no warnings 'once';
    my $err = ''; local $Archive::Zip::ErrorHandler = sub { $err .= "@_" };
    my $zip = Archive::Zip->new;
    UNZIP: {
        my $status = $zip->read($file);
        last UNZIP if $status != Archive::Zip::AZ_OK();
        for my $member ($zip->members) {
            my $af = $member->fileName;
            next if $af =~ m!^(/|\.\./)!;
            my $status = $member->extractToFileNamed($af);
            last UNZIP if $status != Archive::Zip::AZ_OK();
        }
        my ($root) = $zip->membersMatching(qr{^[^/]+/$});
        last UNZIP if !$root;
        $root = $root->fileName;
        $root =~ s{/$}{};
        return $root if -d $root;
    }
    return if !$wantarray;
    return (undef, $err);
}

sub _find_ziproot {
    my ($self, undef, $root, @others) = @_;
    FILE: {
        chomp $root;
        if ($root !~ s{^\s+testing:\s+([^/]+)/.*?\s+OK$}{$1}) {
            $root = shift @others;
            redo FILE if $root;
        }
    }
    $root;
}

1;
