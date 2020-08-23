package App::cpm::Util;
use strict;
use warnings;

use Config;
use Cwd ();
use Digest::MD5 ();
use File::Spec;

use Exporter 'import';

our @EXPORT_OK = qw(perl_identity maybe_abs WIN32 determine_home);

use constant WIN32 => $^O eq 'MSWin32';

sub perl_identity {
    my $digest = Digest::MD5::md5_hex($Config{perlpath} . Config->myconfig);
    $digest = substr $digest, 0, 8;
    join '-', $Config{version}, $Config{archname}, $digest
}

sub maybe_abs {
    my $path = shift;
    if (File::Spec->file_name_is_absolute($path)) {
        return $path;
    }
    my $cwd = shift || Cwd::cwd();
    File::Spec->canonpath(File::Spec->catdir($cwd, $path));
}

sub determine_home { # taken from Menlo
    my $homedir = $ENV{HOME}
      || eval { require File::HomeDir; File::HomeDir->my_home }
      || join('', @ENV{qw(HOMEDRIVE HOMEPATH)}); # Win32

    if (WIN32) {
        require Win32; # no fatpack
        $homedir = Win32::GetShortPathName($homedir);
    }

    File::Spec->catdir($homedir, ".perl-cpm");
}

1;
