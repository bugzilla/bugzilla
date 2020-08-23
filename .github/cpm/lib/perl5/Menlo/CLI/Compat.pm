package Menlo::CLI::Compat;
use strict;
use Config;
use Cwd ();
use Menlo;
use Menlo::Dependency;
use Menlo::Util qw(WIN32);
use File::Basename ();
use File::Find ();
use File::Path ();
use File::Spec ();
use File::Copy ();
use File::Temp ();
use File::Which qw(which);
use Getopt::Long ();
use Symbol ();
use version ();

use constant BAD_TAR => ($^O eq 'solaris' || $^O eq 'hpux');
use constant CAN_SYMLINK => eval { symlink("", ""); 1 };

our $VERSION = '1.9022';

if ($INC{"App/FatPacker/Trace.pm"}) {
    require version::vpp;
}

sub qs($) {
    Menlo::Util::shell_quote($_[0]);
}

sub determine_home {
    my $class = shift;

    my $homedir = $ENV{HOME}
      || eval { require File::HomeDir; File::HomeDir->my_home }
      || join('', @ENV{qw(HOMEDRIVE HOMEPATH)}); # Win32

    if (WIN32) {
        require Win32; # no fatpack
        $homedir = Win32::GetShortPathName($homedir);
    }

    return "$homedir/.cpanm";
}

sub new {
    my $class = shift;

    my $self = bless {
        name => "Menlo",
        home => $class->determine_home,
        cmd  => 'install',
        seen => {},
        notest => undef,
        test_only => undef,
        installdeps => undef,
        force => undef,
        sudo => undef,
        make  => undef,
        verbose => undef,
        quiet => undef,
        interactive => undef,
        log => undef,
        mirrors => [],
        mirror_only => undef,
        mirror_index => undef,
        cpanmetadb => "http://cpanmetadb.plackperl.org/v1.0/",
        perl => $^X,
        argv => [],
        local_lib => undef,
        self_contained => undef,
        exclude_vendor => undef,
        prompt_timeout => 0,
        prompt => undef,
        configure_timeout => 60,
        build_timeout => 3600,
        test_timeout => 1800,
        try_lwp => 1,
        try_wget => 1,
        try_curl => 1,
        uninstall_shadows => ($] < 5.012),
        skip_installed => 1,
        skip_satisfied => 0,
        static_install => 1,
        auto_cleanup => 7, # days
        pod2man => 1,
        installed_dists => 0,
        install_types => ['requires'],
        with_develop => 0,
        with_configure => 0,
        showdeps => 0,
        scandeps => 0,
        scandeps_tree => [],
        format   => 'tree',
        save_dists => undef,
        skip_configure => 0,
        verify => 0,
        report_perl_version => !$class->maybe_ci,
        build_args => {},
        features => {},
        pure_perl => 0,
        cpanfile_path => 'cpanfile',
        @_,
    }, $class;

    $self;
}

sub env {
    my($self, $key) = @_;
    $ENV{"PERL_CPANM_" . $key};
}

sub maybe_ci {
    my $class = shift;
    grep $ENV{$_}, qw( TRAVIS CI AUTOMATED_TESTING AUTHOR_TESTING );
}

sub install_type_handlers {
    my $self = shift;

    my @handlers;
    for my $type (qw( recommends suggests )) {
        push @handlers, "with-$type" => sub {
            my %uniq;
            $self->{install_types} = [ grep !$uniq{$_}++, @{$self->{install_types}}, $type ];
        };
        push @handlers, "without-$type" => sub {
            $self->{install_types} = [ grep $_ ne $type, @{$self->{install_types}} ];
        };
    }

    @handlers;
}

sub build_args_handlers {
    my $self = shift;

    my @handlers;
    for my $phase (qw( configure build test install )) {
        push @handlers, "$phase-args=s" => \($self->{build_args}{$phase});
    }

    @handlers;
}

sub parse_options {
    my $self = shift;

    local @ARGV = @{$self->{argv}};
    push @ARGV, grep length, split /\s+/, $self->env('OPT');
    push @ARGV, @_;

    Getopt::Long::Configure("bundling");
    Getopt::Long::GetOptions(
        'f|force'   => sub { $self->{skip_installed} = 0; $self->{force} = 1 },
        'n|notest!' => \$self->{notest},
        'test-only' => sub { $self->{notest} = 0; $self->{skip_installed} = 0; $self->{test_only} = 1 },
        'S|sudo!'   => \$self->{sudo},
        'v|verbose' => \$self->{verbose},
        'verify!'   => \$self->{verify},
        'q|quiet!'  => \$self->{quiet},
        'h|help'    => sub { $self->{action} = 'show_help' },
        'V|version' => sub { $self->{action} = 'show_version' },
        'perl=s'    => sub {
            $self->diag("--perl is deprecated since it's known to be fragile in figuring out dependencies. Run `$_[1] -S cpanm` instead.\n", 1);
            $self->{perl} = $_[1];
        },
        'l|local-lib=s' => sub { $self->{local_lib} = $self->maybe_abs($_[1]) },
        'L|local-lib-contained=s' => sub {
            $self->{local_lib} = $self->maybe_abs($_[1]);
            $self->{self_contained} = 1;
            $self->{pod2man} = undef;
        },
        'self-contained!' => \$self->{self_contained},
        'exclude-vendor!' => \$self->{exclude_vendor},
        'mirror=s@' => $self->{mirrors},
        'mirror-only!' => \$self->{mirror_only},
        'mirror-index=s' => sub { $self->{mirror_index} = $self->maybe_abs($_[1]) },
        'M|from=s' => sub {
            $self->{mirrors}     = [$_[1]];
            $self->{mirror_only} = 1;
        },
        'cpanmetadb=s'    => \$self->{cpanmetadb},
        'cascade-search!' => \$self->{cascade_search},
        'prompt!'   => \$self->{prompt},
        'installdeps' => \$self->{installdeps},
        'skip-installed!' => \$self->{skip_installed},
        'skip-satisfied!' => \$self->{skip_satisfied},
        'reinstall'    => sub { $self->{skip_installed} = 0 },
        'interactive!' => \$self->{interactive},
        'i|install'    => sub { $self->{cmd} = 'install' },
        'info'         => sub { $self->{cmd} = 'info' },
        'look'         => sub { $self->{cmd} = 'look'; $self->{skip_installed} = 0 },
        'U|uninstall'  => sub { $self->{cmd} = 'uninstall' },
        'self-upgrade' => sub { $self->{action} = 'self_upgrade' },
        'uninst-shadows!'  => \$self->{uninstall_shadows},
        'lwp!'    => \$self->{try_lwp},
        'wget!'   => \$self->{try_wget},
        'curl!'   => \$self->{try_curl},
        'auto-cleanup=s' => \$self->{auto_cleanup},
        'man-pages!' => \$self->{pod2man},
        'scandeps'   => \$self->{scandeps},
        'showdeps'   => sub { $self->{showdeps} = 1; $self->{skip_installed} = 0 },
        'format=s'   => \$self->{format},
        'save-dists=s' => sub {
            $self->{save_dists} = $self->maybe_abs($_[1]);
        },
        'skip-configure!' => \$self->{skip_configure},
        'static-install!' => \$self->{static_install},
        'dev!'       => \$self->{dev_release},
        'metacpan!'  => \$self->{metacpan},
        'report-perl-version!' => \$self->{report_perl_version},
        'configure-timeout=i' => \$self->{configure_timeout},
        'build-timeout=i' => \$self->{build_timeout},
        'test-timeout=i' => \$self->{test_timeout},
        'with-develop' => \$self->{with_develop},
        'without-develop' => sub { $self->{with_develop} = 0 },
        'with-configure' => \$self->{with_configure},
        'without-configure' => sub { $self->{with_configure} = 0 },
        'with-feature=s' => sub { $self->{features}{$_[1]} = 1 },
        'without-feature=s' => sub { $self->{features}{$_[1]} = 0 },
        'with-all-features' => sub { $self->{features}{__all} = 1 },
        'pp|pureperl!' => \$self->{pure_perl},
        "cpanfile=s" => \$self->{cpanfile_path},
        $self->install_type_handlers,
        $self->build_args_handlers,
    );

    if (!@ARGV && $0 ne '-' && !-t STDIN){ # e.g. # cpanm < author/requires.cpanm
        push @ARGV, $self->load_argv_from_fh(\*STDIN);
        $self->{load_from_stdin} = 1;
    }

    $self->{argv} = \@ARGV;
}

sub check_upgrade {
    my $self = shift;
    my $install_base = $ENV{PERL_LOCAL_LIB_ROOT} ? $self->local_lib_target($ENV{PERL_LOCAL_LIB_ROOT}) : $Config{installsitebin};
    if ($0 eq '-') {
        # run from curl, that's fine
        return;
    } elsif ($0 !~ /^$install_base/) {
        if ($0 =~ m!perlbrew/bin!) {
            die <<DIE;
It appears your cpanm executable was installed via `perlbrew install-cpanm`.
cpanm --self-upgrade won't upgrade the version of cpanm you're running.

Run the following command to get it upgraded.

  perlbrew install-cpanm

DIE
        } else {
            die <<DIE;
You are running cpanm from the path where your current perl won't install executables to.
Because of that, cpanm --self-upgrade won't upgrade the version of cpanm you're running.

  cpanm path   : $0
  Install path : $Config{installsitebin}

It means you either installed cpanm globally with system perl, or use distro packages such
as rpm or apt-get, and you have to use them again to upgrade cpanm.
DIE
        }
    }
}

sub check_libs {
    my $self = shift;
    return if $self->{_checked}++;
    $self->bootstrap_local_lib;
}

sub setup_verify {
    my $self = shift;

    my $has_modules = eval { require Module::Signature; require Digest::SHA; 1 };
    $self->{cpansign} = which('cpansign');

    unless ($has_modules && $self->{cpansign}) {
        warn "WARNING: Module::Signature and Digest::SHA is required for distribution verifications.\n";
        $self->{verify} = 0;
    }
}

sub parse_module_args {
    my($self, $module) = @_;

    # Plack@1.2 -> Plack~"==1.2"
    # BUT don't expand @ in git URLs
    $module =~ s/^([A-Za-z0-9_:]+)@([v\d\._]+)$/$1~== $2/;

    # Plack~1.20, DBI~"> 1.0, <= 2.0"
    if ($module =~ /\~[v\d\._,\!<>= ]+$/) {
        return split '~', $module, 2;
    } else {
        return $module, undef;
    }
}

sub run {
    my $self = shift;

    my $code;
    eval {
        $code = ($self->_doit == 0);
    }; if (my $e = $@) {
        warn $e;
        $code = 1;
    }

    $self->{status} = $code;
}

sub status {
    $_[0]->{status};
}

sub _doit {
    my $self = shift;

    $self->setup_home;
    $self->init_tools;
    $self->setup_verify if $self->{verify};

    if (my $action = $self->{action}) {
        $self->$action() and return 1;
    }

    return $self->show_help(1)
        unless @{$self->{argv}} or $self->{load_from_stdin};

    $self->configure_mirrors;

    my $cwd = Cwd::cwd;

    my @fail;
    for my $module (@{$self->{argv}}) {
        if ($module =~ s/\.pm$//i) {
            my ($volume, $dirs, $file) = File::Spec->splitpath($module);
            $module = join '::', grep { $_ } File::Spec->splitdir($dirs), $file;
        }
        ($module, my $version) = $self->parse_module_args($module);

        $self->chdir($cwd);
        if ($self->{cmd} eq 'uninstall') {
            $self->uninstall_module($module)
              or push @fail, $module;
        } else {
            $self->install_module($module, 0, $version)
                or push @fail, $module;
        }
    }

    if ($self->{base} && $self->{auto_cleanup}) {
        $self->cleanup_workdirs;
    }

    if ($self->{installed_dists}) {
        my $dists = $self->{installed_dists} > 1 ? "distributions" : "distribution";
        $self->diag("$self->{installed_dists} $dists installed\n", 1);
    }

    if ($self->{scandeps}) {
        $self->dump_scandeps();
    }
    # Workaround for older File::Temp's
    # where creating a tempdir with an implicit $PWD
    # causes tempdir non-cleanup if $PWD changes
    # as paths are stored internally without being resolved
    # absolutely.
    # https://rt.cpan.org/Public/Bug/Display.html?id=44924
    $self->chdir($cwd);

    return !@fail;
}

sub setup_home {
    my $self = shift;

    $self->{home} = $self->env('HOME') if $self->env('HOME');

    unless (_writable($self->{home})) {
        die "Can't write to cpanm home '$self->{home}': You should fix it with chown/chmod first.\n";
    }

    $self->{base} = "$self->{home}/work/" . time . ".$$";
    File::Path::mkpath([ $self->{base} ], 0, 0777);

    # native path because we use shell redirect
    $self->{log} = File::Spec->catfile($self->{base}, "build.log");
    my $final_log = "$self->{home}/build.log";

    { open my $out, ">$self->{log}" or die "$self->{log}: $!" }

    if (CAN_SYMLINK) {
        my $build_link = "$self->{home}/latest-build";
        unlink $build_link;
        symlink $self->{base}, $build_link;

        unlink $final_log;
        symlink $self->{log}, $final_log;
    } else {
        my $log = $self->{log}; my $home = $self->{home};
        $self->{at_exit} = sub {
            my $self = shift;
            my $temp_log = "$home/build.log." . time . ".$$";
            File::Copy::copy($log, $temp_log)
                && unlink($final_log);
            rename($temp_log, $final_log);
        }
    }

    $self->chat("cpanm ($self->{name}) $Menlo::VERSION on perl $] built for $Config{archname}\n" .
                "Work directory is $self->{base}\n");
}

sub search_mirror_index_local {
    my ($self, $local, $module, $version) = @_;
    require CPAN::Common::Index::LocalPackage;
    my $index = CPAN::Common::Index::LocalPackage->new({ source => $local });
    $self->search_common($index, { package => $module }, $version);
}

sub search_mirror_index {
    my ($self, $mirror, $module, $version) = @_;
    require Menlo::Index::Mirror;
    my $index = Menlo::Index::Mirror->new({
        mirror => $mirror,
        cache => $self->source_for($mirror),
        fetcher => sub { $self->mirror(@_) },
    });
    $self->search_common($index, { package => $module }, $version);
}

sub search_common {
    my($self, $index, $search_args, $want_version) = @_;

    $index->refresh_index;

    my $found = $index->search_packages($search_args);
    $found = $self->cpan_module_common($found) if $found;

    return $found unless $self->{cascade_search};

    if ($found) {
        if ($self->satisfy_version($found->{module}, $found->{module_version}, $want_version)) {
            return $found;
        } else {
            $self->chat("Found $found->{module} $found->{module_version} which doesn't satisfy $want_version.\n");
        }
    }
    
    return;
}

sub with_version_range {
    my($self, $version) = @_;
    defined($version) && $version =~ /(?:<|!=|==)/;
}

sub search_metacpan {
    my($self, $module, $version, $dev_release) = @_;

    require Menlo::Index::MetaCPAN;
    $self->chat("Searching $module ($version) on metacpan ...\n");

    my $index = Menlo::Index::MetaCPAN->new({ include_dev => $self->{dev_release} });
    my $pkg = $self->search_common($index, { package => $module, version_range => $version }, $version);
    return $pkg if $pkg;

    $self->diag_fail("Finding $module ($version) on metacpan failed.");
    return;
}

sub search_database {
    my($self, $module, $version) = @_;

    my $found;

    if ($self->{dev_release} or $self->{metacpan}) {
        $found = $self->search_metacpan($module, $version, $self->{dev_release})   and return $found;
        $found = $self->search_cpanmetadb($module, $version, $self->{dev_release}) and return $found;
    } else {
        $found = $self->search_cpanmetadb($module, $version) and return $found;
        $found = $self->search_metacpan($module, $version)   and return $found;
    }
}

sub search_cpanmetadb {
    my($self, $module, $version, $dev_release) = @_;

    require Menlo::Index::MetaDB;
    $self->chat("Searching $module ($version) on cpanmetadb ...\n");

    my $args = { package => $module };
    if ($self->with_version_range($version)) {
        $args->{version_range} = $version;
    }

    my $index = Menlo::Index::MetaDB->new({ uri => $self->{cpanmetadb} });
    my $pkg = $self->search_common($index, $args, $version);
    return $pkg if $pkg;

    $self->diag_fail("Finding $module on cpanmetadb failed.");
    return;
}

sub search_module {
    my($self, $module, $version) = @_;

    if ($self->{mirror_index}) {
        $self->mask_output( chat => "Searching $module on mirror index $self->{mirror_index} ...\n" );
        my $pkg = $self->search_mirror_index_local($self->{mirror_index}, $module, $version);
        return $pkg if $pkg;

        unless ($self->{cascade_search}) {
           $self->mask_output( diag_fail => "Finding $module ($version) on mirror index $self->{mirror_index} failed." );
           return;
        }
    }

    unless ($self->{mirror_only}) {
        my $found = $self->search_database($module, $version);
        return $found if $found;
    }

    MIRROR: for my $mirror (@{ $self->{mirrors} }) {
        $self->mask_output( chat => "Searching $module on mirror $mirror ...\n" );

        my $pkg = $self->search_mirror_index($mirror, $module, $version);
        return $pkg if $pkg;

        $self->mask_output( diag_fail => "Finding $module ($version) on mirror $mirror failed." );
    }

    return;
}

sub source_for {
    my($self, $mirror) = @_;
    $mirror =~ s/[^\w\.\-]+/%/g;

    my $dir = "$self->{home}/sources/$mirror";
    File::Path::mkpath([ $dir ], 0, 0777);

    return $dir;
}

sub load_argv_from_fh {
    my($self, $fh) = @_;

    my @argv;
    while(defined(my $line = <$fh>)){
        chomp $line;
        $line =~ s/#.+$//; # comment
        $line =~ s/^\s+//; # trim spaces
        $line =~ s/\s+$//; # trim spaces

        push @argv, split ' ', $line if $line;
    }
    return @argv;
}

sub show_version {
    my $self = shift;

    print "cpanm ($self->{name}) version $VERSION ($0)\n";
    print "perl version $] ($^X)\n\n";

    print "  \%Config:\n";
    for my $key (qw( archname installsitelib installsitebin installman1dir installman3dir
                     sitearchexp sitelibexp vendorarch vendorlibexp archlibexp privlibexp )) {
        print "    $key=$Config{$key}\n" if $Config{$key};
    }

    print "  \%ENV:\n";
    for my $key (grep /^PERL/, sort keys %ENV) {
        print "    $key=$ENV{$key}\n";
    }

    print "  \@INC:\n";
    for my $inc (@INC) {
        print "    $inc\n" unless ref($inc) eq 'CODE';
    }

    return 1;
}

sub show_help {
    my $self = shift;

    if ($_[0]) {
        print <<USAGE;
Usage: cpanm [options] Module [...]

Try `cpanm --help` or `man cpanm` for more options.
USAGE
        return;
    }

    print <<HELP;
Usage: cpanm [options] Module [...]

Options:
  -v,--verbose              Turns on chatty output
  -q,--quiet                Turns off the most output
  --interactive             Turns on interactive configure (required for Task:: modules)
  -f,--force                force install
  -n,--notest               Do not run unit tests
  --test-only               Run tests only, do not install
  -S,--sudo                 sudo to run install commands
  --installdeps             Only install dependencies
  --showdeps                Only display direct dependencies
  --reinstall               Reinstall the distribution even if you already have the latest version installed
  --mirror                  Specify the base URL for the mirror (e.g. http://cpan.cpantesters.org/)
  --mirror-only             Use the mirror's index file instead of the CPAN Meta DB
  -M,--from                 Use only this mirror base URL and its index file
  --prompt                  Prompt when configure/build/test fails
  -l,--local-lib            Specify the install base to install modules
  -L,--local-lib-contained  Specify the install base to install all non-core modules
  --self-contained          Install all non-core modules, even if they're already installed.
  --auto-cleanup            Number of days that cpanm's work directories expire in. Defaults to 7

Commands:
  --self-upgrade            upgrades itself
  --info                    Displays distribution info on CPAN
  --look                    Opens the distribution with your SHELL
  -U,--uninstall            Uninstalls the modules (EXPERIMENTAL)
  -V,--version              Displays software version

Examples:

  cpanm Test::More                                          # install Test::More
  cpanm MIYAGAWA/Plack-0.99_05.tar.gz                       # full distribution path
  cpanm http://example.org/LDS/CGI.pm-3.20.tar.gz           # install from URL
  cpanm ~/dists/MyCompany-Enterprise-1.00.tar.gz            # install from a local file
  cpanm --interactive Task::Kensho                          # Configure interactively
  cpanm .                                                   # install from local directory
  cpanm --installdeps .                                     # install all the deps for the current directory
  cpanm -L extlib Plack                                     # install Plack and all non-core deps into extlib
  cpanm --mirror http://cpan.cpantesters.org/ DBI           # use the fast-syncing mirror
  cpanm -M https://cpan.metacpan.org App::perlbrew          # use only this secure mirror and its index

You can also specify the default options in PERL_CPANM_OPT environment variable in the shell rc:

  export PERL_CPANM_OPT="--prompt --reinstall -l ~/perl --mirror http://cpan.cpantesters.org"

Type `man cpanm` or `perldoc cpanm` for the more detailed explanation of the options.

HELP

    return 1;
}

sub _writable {
    my $dir = shift;
    my @dir = File::Spec->splitdir($dir);
    while (@dir) {
        $dir = File::Spec->catdir(@dir);
        if (-e $dir) {
            return -w _;
        }
        pop @dir;
    }

    return;
}

sub maybe_abs {
    my($self, $lib) = @_;
    if ($lib eq '_' or $lib =~ /^~/ or File::Spec->file_name_is_absolute($lib)) {
        return $lib;
    } else {
        return File::Spec->canonpath(File::Spec->catdir(Cwd::cwd(), $lib));
    }
}

sub local_lib_target {
    my($self, $root) = @_;
    # local::lib 1.008025 changed the order of PERL_LOCAL_LIB_ROOT
    (grep { $_ ne '' } split /\Q$Config{path_sep}/, $root)[0];
}

sub bootstrap_local_lib {
    my $self = shift;

    # If -l is specified, use that.
    if ($self->{local_lib}) {
        return $self->setup_local_lib($self->{local_lib});
    }

    # PERL_LOCAL_LIB_ROOT is defined. Run as local::lib mode without overwriting ENV
    if ($ENV{PERL_LOCAL_LIB_ROOT} && $ENV{PERL_MM_OPT}) {
        return $self->setup_local_lib($self->local_lib_target($ENV{PERL_LOCAL_LIB_ROOT}), 1);
    }

    # root, locally-installed perl or --sudo: don't care about install_base
    return if $self->{sudo} or (_writable($Config{installsitelib}) and _writable($Config{installsitebin}));

    # local::lib is configured in the shell -- yay
    if ($ENV{PERL_MM_OPT} and ($ENV{MODULEBUILDRC} or $ENV{PERL_MB_OPT})) {
        return;
    }

    $self->setup_local_lib;

    $self->diag(<<DIAG, 1);
!
! Can't write to $Config{installsitelib} and $Config{installsitebin}: Installing modules to $ENV{HOME}/perl5
! To turn off this warning, you have to do one of the following:
!   - run me as a root or with --sudo option (to install to $Config{installsitelib} and $Config{installsitebin})
!   - Configure local::lib in your existing shell to set PERL_MM_OPT etc.
!   - Install local::lib by running the following commands
!
!         cpanm --local-lib=~/perl5 local::lib && eval \$(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
!
DIAG
    sleep 2;
}

sub upgrade_toolchain {
    my($self, $config_deps) = @_;

    my %deps = map { $_->module => $_ } @$config_deps;

    # M::B 0.38 and EUMM 6.58 for MYMETA
    # EU::Install 1.46 for local::lib
    my $reqs = CPAN::Meta::Requirements->from_string_hash({
        'Module::Build' => '0.38',
        'ExtUtils::MakeMaker' => '6.58',
        'ExtUtils::Install' => '1.46',
    });

    if ($deps{"ExtUtils::MakeMaker"}) {
        $deps{"ExtUtils::MakeMaker"}->merge_with($reqs);
    } elsif ($deps{"Module::Build"}) {
        $deps{"Module::Build"}->merge_with($reqs);
        $deps{"ExtUtils::Install"} ||= Menlo::Dependency->new("ExtUtils::Install", 0, 'configure');
        $deps{"ExtUtils::Install"}->merge_with($reqs);
    }

    @$config_deps = values %deps;
}

sub _core_only_inc {
    my($self, $base) = @_;
    require local::lib;
    (
        local::lib->resolve_path(local::lib->install_base_arch_path($base)),
        local::lib->resolve_path(local::lib->install_base_perl_path($base)),
        (!$self->{exclude_vendor} ? grep {$_} @Config{qw(vendorarch vendorlibexp)} : ()),
        @Config{qw(archlibexp privlibexp)},
    );
}

sub _setup_local_lib_env {
    my($self, $base) = @_;

    $self->diag(<<WARN, 1) if $base =~ /\s/;
WARNING: Your lib directory name ($base) contains a space in it. It's known to cause issues with perl builder tools such as local::lib and MakeMaker. You're recommended to rename your directory.
WARN

    local $SIG{__WARN__} = sub { }; # catch 'Attempting to write ...'
    local::lib->setup_env_hash_for($base, 0);
}

sub setup_local_lib {
    my($self, $base, $no_env) = @_;
    $base = undef if $base eq '_';

    require local::lib;
    {
        local $0 = 'cpanm'; # so curl/wget | perl works
        $base ||= "~/perl5";
        $base = local::lib->resolve_path($base);
        if ($self->{self_contained}) {
            my @inc = $self->_core_only_inc($base);
            $self->{search_inc} = [ @inc ];
        } else {
            $self->{search_inc} = [
                local::lib->install_base_arch_path($base),
                local::lib->install_base_perl_path($base),
                @INC,
            ];
        }
        $self->_setup_local_lib_env($base) unless $no_env;
        $self->{local_lib} = $base;
    }
}

sub prompt_bool {
    my($self, $mess, $def) = @_;

    my $val = $self->prompt($mess, $def);
    return lc $val eq 'y';
}

sub prompt {
    my($self, $mess, $def) = @_;

    my $isa_tty = -t STDIN && (-t STDOUT || !(-f STDOUT || -c STDOUT)) ;
    my $dispdef = defined $def ? "[$def] " : " ";
    $def = defined $def ? $def : "";

    if (!$self->{prompt} || (!$isa_tty && eof STDIN)) {
        return $def;
    }

    local $|=1;
    local $\;
    my $ans;
    eval {
        local $SIG{ALRM} = sub { undef $ans; die "alarm\n" };
        print STDOUT "$mess $dispdef";
        alarm $self->{prompt_timeout} if $self->{prompt_timeout};
        $ans = <STDIN>;
        alarm 0;
    };
    if ( defined $ans ) {
        chomp $ans;
    } else { # user hit ctrl-D or alarm timeout
        print STDOUT "\n";
    }

    return (!defined $ans || $ans eq '') ? $def : $ans;
}

sub diag_ok {
    my($self, $msg) = @_;
    chomp $msg;
    $msg ||= "OK";
    if ($self->{in_progress}) {
        $self->_diag("$msg\n");
        $self->{in_progress} = 0;
    }
    $self->log("-> $msg\n");
}

sub diag_fail {
    my($self, $msg, $always) = @_;
    chomp $msg;
    if ($self->{in_progress}) {
        $self->_diag("FAIL\n");
        $self->{in_progress} = 0;
    }

    if ($msg) {
        $self->_diag("! $msg\n", $always, 1);
        $self->log("-> FAIL $msg\n");
    }
}

sub diag_progress {
    my($self, $msg) = @_;
    chomp $msg;
    $self->{in_progress} = 1;
    $self->_diag("$msg ... ");
    $self->log("$msg\n");
}

sub _diag {
    my($self, $msg, $always, $error) = @_;
    my $fh = $error ? *STDERR : *STDOUT;
    print {$fh} $msg if $always or $self->{verbose} or !$self->{quiet};
}

sub diag {
    my($self, $msg, $always) = @_;
    $self->_diag($msg, $always);
    $self->log($msg);
}

sub chat {
    my $self = shift;
    print STDERR @_ if $self->{verbose};
    $self->log(@_);
}

sub mask_output {
    my $self = shift;
    my $method = shift;
    $self->$method( $self->mask_uri_passwords(@_) );
}

sub log {
    my $self = shift;
    open my $out, ">>$self->{log}";
    print $out @_;
}

sub run_command {
    my($self, $cmd) = @_;

    # TODO move to a more appropriate runner method
    if (ref $cmd eq 'CODE') {
        if ($self->{verbose}) {
            return $cmd->();
        } else {
            require Capture::Tiny;
            open my $logfh, ">>", $self->{log};
            my $ret;
            Capture::Tiny::capture(sub { $ret = $cmd->() }, stdout => $logfh, stderr => $logfh);
            return $ret;
        }
    }

    if (WIN32) {
        $cmd = Menlo::Util::shell_quote(@$cmd) if ref $cmd eq 'ARRAY';
        unless ($self->{verbose}) {
            $cmd .= " >> " . Menlo::Util::shell_quote($self->{log}) . " 2>&1";
        }
        !system $cmd;
    } else {
        my $pid = fork;
        if ($pid) {
            waitpid $pid, 0;
            return !$?;
        } else {
            $self->run_exec($cmd);
        }
    }
}

sub run_exec {
    my($self, $cmd) = @_;

    if (ref $cmd eq 'ARRAY') {
        unless ($self->{verbose}) {
            open my $logfh, ">>", $self->{log};
            open STDERR, '>&', $logfh;
            open STDOUT, '>&', $logfh;
            close $logfh;
        }
        exec @$cmd;
    } else {
        unless ($self->{verbose}) {
            $cmd .= " >> " . Menlo::Util::shell_quote($self->{log}) . " 2>&1";
        }
        exec $cmd;
    }
}

sub run_timeout {
    my($self, $cmd, $timeout) = @_;

    return $self->run_command($cmd) if ref($cmd) eq 'CODE' || WIN32 || $self->{verbose} || !$timeout;

    my $pid = fork;
    if ($pid) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $timeout;
            waitpid $pid, 0;
            alarm 0;
        };
        if ($@ && $@ eq "alarm\n") {
            $self->diag_fail("Timed out (> ${timeout}s). Use --verbose to retry.");
            local $SIG{TERM} = 'IGNORE';
            kill TERM => 0;
            waitpid $pid, 0;
            return;
        }
        return !$?;
    } elsif ($pid == 0) {
        $self->run_exec($cmd);
    } else {
        $self->chat("! fork failed: falling back to system()\n");
        $self->run_command($cmd);
    }
}

sub append_args {
    my($self, $cmd, $phase) = @_;

    return $cmd if ref $cmd ne 'ARRAY';
    
    if (my $args = $self->{build_args}{$phase}) {
        $cmd = join ' ', Menlo::Util::shell_quote(@$cmd), $args;
    }

    $cmd;
}

sub _use_unsafe_inc {
    my($self, $dist) = @_;

    # if it's set in the env (i.e. user's shell), just use that
    if (exists $ENV{PERL_USE_UNSAFE_INC}) {
        return $ENV{PERL_USE_UNSAFE_INC};
    }

    # it's set in CPAN Meta, prefer what the author says
    if (exists $dist->{meta}{x_use_unsafe_inc}) {
        $self->chat("Distribution opts in x_use_unsafe_inc: $dist->{meta}{x_use_unsafe_inc}\n");
        return $dist->{meta}{x_use_unsafe_inc};
    }

    # otherwise set to 1 as a default to allow for old modules
    return 1;
}

sub configure {
    my($self, $cmd, $dist, $depth) = @_;

    # trick AutoInstall
    local $ENV{PERL5_CPAN_IS_RUNNING} = local $ENV{PERL5_CPANPLUS_IS_RUNNING} = $$;

    # e.g. skip CPAN configuration on local::lib
    local $ENV{PERL5_CPANM_IS_RUNNING} = $$;

    my $use_default = !$self->{interactive};
    local $ENV{PERL_MM_USE_DEFAULT} = $use_default;

    local $ENV{PERL_MM_OPT} = $ENV{PERL_MM_OPT};
    local $ENV{PERL_MB_OPT} = $ENV{PERL_MB_OPT};

    # skip man page generation
    unless ($self->{pod2man}) {
        $ENV{PERL_MM_OPT} .= " INSTALLMAN1DIR=none INSTALLMAN3DIR=none";
        $ENV{PERL_MB_OPT} .= " --config installman1dir= --config installsiteman1dir= --config installman3dir= --config installsiteman3dir=";
    }

    # Lancaster Consensus
    if ($self->{pure_perl}) {
        $ENV{PERL_MM_OPT} .= " PUREPERL_ONLY=1";
        $ENV{PERL_MB_OPT} .= " --pureperl-only";
    }

    local $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($dist);

    $cmd = $self->append_args($cmd, 'configure') if $depth == 0;

    local $self->{verbose} = $self->{verbose} || $self->{interactive};
    $self->run_timeout($cmd, $self->{configure_timeout});
}

sub build {
    my($self, $cmd, $distname, $dist, $depth) = @_;

    local $ENV{PERL_MM_USE_DEFAULT} = !$self->{interactive};

    local $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($dist);

    $cmd = $self->append_args($cmd, 'build') if $depth == 0;

    return 1 if $self->run_timeout($cmd, $self->{build_timeout});
    while (1) {
        my $ans = lc $self->prompt("Building $distname failed.\nYou can s)kip, r)etry, e)xamine build log, or l)ook ?", "s");
        return                                              if $ans eq 's';
        return $self->build($cmd, $distname, $dist, $depth) if $ans eq 'r';
        $self->show_build_log                               if $ans eq 'e';
        $self->look                                         if $ans eq 'l';
    }
}

sub test {
    my($self, $cmd, $distname, $dist, $depth) = @_;
    return 1 if $self->{notest};

    # https://rt.cpan.org/Ticket/Display.html?id=48965#txn-1013385
    local $ENV{PERL_MM_USE_DEFAULT} = !$self->{interactive};

    # https://github.com/Perl-Toolchain-Gang/toolchain-site/blob/master/lancaster-consensus.md
    local $ENV{NONINTERACTIVE_TESTING} = !$self->{interactive};

    local $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($dist);

    $cmd = $self->append_args($cmd, 'test') if $depth == 0;

    return 1 if $self->run_timeout($cmd, $self->{test_timeout});
    if ($self->{force}) {
        $self->diag_fail("Testing $distname failed but installing it anyway.");
        return 1;
    } else {
        $self->diag_fail;
        while (1) {
            my $ans = lc $self->prompt("Testing $distname failed.\nYou can s)kip, r)etry, f)orce install, e)xamine build log, or l)ook ?", "s");
            return                                             if $ans eq 's';
            return $self->test($cmd, $distname, $dist, $depth) if $ans eq 'r';
            return 1                                           if $ans eq 'f';
            $self->show_build_log                              if $ans eq 'e';
            $self->look                                        if $ans eq 'l';
        }
    }
}

sub install {
    my($self, $cmd, $uninst_opts, $dist, $depth) = @_;

    if ($depth == 0 && $self->{test_only}) {
        return 1;
    }

    return $self->run_command($cmd) if ref $cmd eq 'CODE';

    local $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($dist);

    if ($self->{sudo}) {
        unshift @$cmd, "sudo";
    }

    if ($self->{uninstall_shadows} && !$ENV{PERL_MM_OPT}) {
        push @$cmd, @$uninst_opts;
    }

    $cmd = $self->append_args($cmd, 'install') if $depth == 0;

    $self->run_command($cmd);
}

sub look {
    my $self = shift;

    my $shell = $ENV{SHELL};
    $shell  ||= $ENV{COMSPEC} if WIN32;
    if ($shell) {
        my $cwd = Cwd::cwd;
        $self->diag("Entering $cwd with $shell\n");
        system $shell;
    } else {
        $self->diag_fail("You don't seem to have a SHELL :/");
    }
}

sub show_build_log {
    my $self = shift;

    my @pagers = (
        $ENV{PAGER},
        (WIN32 ? () : ('less')),
        'more'
    );
    my $pager;
    while (@pagers) {
        $pager = shift @pagers;
        next unless $pager;
        $pager = which($pager);
        next unless $pager;
        last;
    }

    if ($pager) {
        if (WIN32) {
            system "@{[ qs $pager ]} < @{[ qs $self->{log}]}";
        } else {
            system $pager, $self->{log};
        }
    }
    else {
        $self->diag_fail("You don't seem to have a PAGER :/");
    }
}

sub chdir {
    my $self = shift;
    Cwd::chdir(File::Spec->canonpath($_[0])) or die "$_[0]: $!";
}

sub configure_mirrors {
    my $self = shift;
    unless (@{$self->{mirrors}}) {
        $self->{mirrors} = [ 'http://www.cpan.org' ];
    }
    for (@{$self->{mirrors}}) {
        s!^/!file:///!;
        s!/$!!;
    }
}

sub self_upgrade {
    my $self = shift;
    $self->check_upgrade;
    $self->{argv} = [ 'Menlo' ];
    return; # continue
}

sub install_module {
    my($self, $module, $depth, $version, $dep) = @_;

    $self->check_libs;

    if ($self->{seen}{$module}++) {
        # TODO: circular dependencies
        $self->chat("Already tried $module. Skipping.\n");
        return 1;
    }

    if ($self->{skip_satisfied}) {
        my($ok, $local) = $self->check_module($module, $version || 0);
        if ($ok) {
            $self->diag("You have $module ($local)\n", 1);
            return 1;
        }
    }

    my $dist = $self->resolve_name($module, $version, $dep);
    unless ($dist) {
        my $what = $module . ($version ? " ($version)" : "");
        $self->diag_fail("Couldn't find module or a distribution $what", 1);
        return;
    }

    if ($dist->{distvname} && $self->{seen}{$dist->{distvname}}++) {
        $self->chat("Already tried $dist->{distvname}. Skipping.\n");
        return 1;
    }

    if ($self->{cmd} eq 'info') {
        print $self->format_dist($dist), "\n";
        return 1;
    }

    $dist->{depth} = $depth; # ugly hack

    if ($dist->{module}) {
        unless ($self->satisfy_version($dist->{module}, $dist->{module_version}, $version)) {
            $self->diag("Found $dist->{module} $dist->{module_version} which doesn't satisfy $version.\n", 1);
            return;
        }

        # If a version is requested, it has to be the exact same version, otherwise, check as if
        # it is the minimum version you need.
        my $cmp = $version ? "==" : "";
        my $requirement = $dist->{module_version} ? "$cmp$dist->{module_version}" : 0;
        my($ok, $local) = $self->check_module($dist->{module}, $requirement);
        if ($self->{skip_installed} && $ok) {
            $self->diag("$dist->{module} is up to date. ($local)\n", 1);
            return 1;
        }
    }

    if ($dist->{dist} eq 'perl'){
        $self->diag("skipping $dist->{pathname}\n");
        return 1;
    }

    $self->diag("--> Working on $module\n");

    $dist->{dir} ||= $self->fetch_module($dist);

    unless ($dist->{dir}) {
        $self->diag_fail("Failed to fetch distribution $dist->{distvname}", 1);
        return;
    }

    $self->chat("Entering $dist->{dir}\n");
    $self->chdir($self->{base});
    $self->chdir($dist->{dir});

    if ($self->{cmd} eq 'look') {
        $self->look;
        return 1;
    }

    return $self->build_stuff($module, $dist, $depth);
}

sub uninstall_search_path {
    my $self = shift;

    $self->{local_lib}
        ? (local::lib->install_base_arch_path($self->{local_lib}),
           local::lib->install_base_perl_path($self->{local_lib}))
        : @Config{qw(installsitearch installsitelib)};
}

sub uninstall_module {
    my ($self, $module) = @_;

    $self->check_libs;

    my @inc = $self->uninstall_search_path;

    my($metadata, $packlist) = $self->packlists_containing($module, \@inc);
    unless ($packlist) {
        $self->diag_fail(<<DIAG, 1);
$module is not found in the following directories and can't be uninstalled.

@{[ join("  \n", map "  $_", @inc) ]}

DIAG
        return;
    }

    my @uninst_files = $self->uninstall_target($metadata, $packlist);

    $self->ask_permission($module, \@uninst_files) or return;
    $self->uninstall_files(@uninst_files, $packlist);

    $self->diag("Successfully uninstalled $module\n", 1);

    return 1;
}

sub packlists_containing {
    my($self, $module, $inc) = @_;

    require Module::Metadata;
    my $metadata = Module::Metadata->new_from_module($module, inc => $inc)
        or return;

    my $packlist;
    my $wanted = sub {
        return unless $_ eq '.packlist' && -f $_;
        for my $file ($self->unpack_packlist($File::Find::name)) {
            $packlist ||= $File::Find::name if $file eq $metadata->filename;
        }
    };

    {
        require File::pushd;
        my $pushd = File::pushd::pushd();
        my @search = grep -d $_, map File::Spec->catdir($_, 'auto'), @$inc;
        File::Find::find($wanted, @search);
    }

    return $metadata, $packlist;
}

sub uninstall_target {
    my($self, $metadata, $packlist) = @_;

    # If the module has a shadow install, or uses local::lib, then you can't just remove
    # all files in .packlist since it might have shadows in there
    if ($self->has_shadow_install($metadata) or $self->{local_lib}) {
        grep $self->should_unlink($_), $self->unpack_packlist($packlist);
    } else {
        $self->unpack_packlist($packlist);
    }
}

sub has_shadow_install {
    my($self, $metadata) = @_;

    # check if you have the module in site_perl *and* perl
    my @shadow = grep defined, map Module::Metadata->new_from_module($metadata->name, inc => [$_]), @INC;
    @shadow >= 2;
}

sub should_unlink {
    my($self, $file) = @_;

    # If local::lib is used, everything under the directory can be safely removed
    # Otherwise, bin and man files might be shared with the shadows i.e. site_perl vs perl
    # This is not 100% safe to keep the script there hoping to work with older version of .pm
    # files in the shadow, but there's nothing you can do about it.
    if ($self->{local_lib}) {
        $file =~ /^\Q$self->{local_lib}\E/;
    } else {
        !(grep $file =~ /^\Q$_\E/, @Config{qw(installbin installscript installman1dir installman3dir)});
    }
}

sub ask_permission {
    my ($self, $module, $files) = @_;

    $self->diag("$module contains the following files:\n\n");
    for my $file (@$files) {
        $self->diag("  $file\n");
    }
    $self->diag("\n");

    return 'force uninstall' if $self->{force};
    local $self->{prompt} = 1;
    return $self->prompt_bool("Are you sure you want to uninstall $module?", 'y');
}

sub unpack_packlist {
    my ($self, $packlist) = @_;
    open my $fh, '<', $packlist or die "$packlist: $!";
    map { chomp; $_ } <$fh>;
}

sub uninstall_files {
    my ($self, @files) = @_;

    $self->diag("\n");

    for my $file (@files) {
        $self->diag("Unlink: $file\n");
        unlink $file or $self->diag_fail("$!: $file");
    }

    $self->diag("\n");

    return 1;
}

sub format_dist {
    my($self, $dist) = @_;

    # TODO support --dist-format?
    return "$dist->{cpanid}/$dist->{filename}";
}

sub trim {
    local $_ = shift;
    tr/\n/ /d;
    s/^\s*|\s*$//g;
    $_;
}

sub fetch_module {
    my($self, $dist) = @_;

    $self->chdir($self->{base});

    for my $uri (@{$dist->{uris}}) {
        $self->mask_output( diag_progress => "Fetching $uri" );

        # Ugh, $dist->{filename} can contain sub directory
        my $filename = $dist->{filename} || $uri;
        my $name = File::Basename::basename($filename);

        my $cancelled;
        my $fetch = sub {
            my $file;
            eval {
                local $SIG{INT} = sub { $cancelled = 1; die "SIGINT\n" };
                $self->mirror($uri, $name);
                $file = $name if -e $name;
            };
            $self->diag("ERROR: " . trim("$@") . "\n", 1) if $@ && $@ ne "SIGINT\n";
            return $file;
        };

        my($try, $file);
        while ($try++ < 3) {
            $file = $fetch->();
            last if $cancelled or $file;
            $self->mask_output( diag_fail => "Download $uri failed. Retrying ... ");
        }

        if ($cancelled) {
            $self->diag_fail("Download cancelled.");
            return;
        }

        unless ($file) {
            $self->mask_output( diag_fail => "Failed to download $uri");
            next;
        }

        $self->diag_ok;
        $dist->{local_path} = File::Spec->rel2abs($name);

        my $dir = $self->unpack($file, $uri, $dist);
        next unless $dir; # unpack failed

        if (my $save = $self->{save_dists}) {
            # Only distros retrieved from CPAN have a pathname set
            my $path = $dist->{pathname} ? "$save/authors/id/$dist->{pathname}"
                                         : "$save/vendor/$file";
            $self->chat("Copying $name to $path\n");
            File::Path::mkpath([ File::Basename::dirname($path) ], 0, 0777);
            File::Copy::copy($file, $path) or warn $!;
        }

        return $dist, $dir;
    }
}

sub unpack {
    my($self, $file, $uri, $dist) = @_;

    if ($self->{verify}) {
        $self->verify_archive($file, $uri, $dist) or return;
    }

    $self->chat("Unpacking $file\n");
    my $dir = $file =~ /\.zip/i ? $self->unzip($file) : $self->untar($file);
    unless ($dir) {
        $self->diag_fail("Failed to unpack $file: no directory");
    }
    return $dir;
}

sub verify_checksums_signature {
    my($self, $chk_file) = @_;

    require Module::Signature; # no fatpack

    $self->chat("Verifying the signature of CHECKSUMS\n");

    my $rv = eval {
        local $SIG{__WARN__} = sub {}; # suppress warnings
        my $v = Module::Signature::_verify($chk_file);
        $v == Module::Signature::SIGNATURE_OK();
    };
    if ($rv) {
        $self->chat("Verified OK!\n");
    } else {
        $self->diag_fail("Verifying CHECKSUMS signature failed: $rv\n");
        return;
    }

    return 1;
}

sub verify_archive {
    my($self, $file, $uri, $dist) = @_;

    unless ($dist->{cpanid}) {
        $self->chat("Archive '$file' does not seem to be from PAUSE. Skip verification.\n");
        return 1;
    }

    (my $mirror = $uri) =~ s!/authors/id.*$!!;

    (my $chksum_uri = $uri) =~ s!/[^/]*$!/CHECKSUMS!;
    my $chk_file = $self->source_for($mirror) . "/$dist->{cpanid}.CHECKSUMS";
    $self->mask_output( diag_progress => "Fetching $chksum_uri" );
    $self->mirror($chksum_uri, $chk_file);

    unless (-e $chk_file) {
        $self->diag_fail("Fetching $chksum_uri failed.\n");
        return;
    }

    $self->diag_ok;
    $self->verify_checksums_signature($chk_file) or return;
    $self->verify_checksum($file, $chk_file);
}

sub verify_checksum {
    my($self, $file, $chk_file) = @_;

    $self->chat("Verifying the SHA1 for $file\n");

    open my $fh, "<$chk_file" or die "$chk_file: $!";
    my $data = join '', <$fh>;
    $data =~ s/\015?\012/\n/g;

    require Safe; # no fatpack
    my $chksum = Safe->new->reval($data);

    if (!ref $chksum or ref $chksum ne 'HASH') {
        $self->diag_fail("! Checksum file downloaded from $chk_file is broken.\n");
        return;
    }

    if (my $sha = $chksum->{$file}{sha256}) {
        my $hex = $self->sha_for(256, $file);
        if ($hex eq $sha) {
            $self->chat("Checksum for $file: Verified!\n");
        } else {
            $self->diag_fail("Checksum mismatch for $file\n");
            return;
        }
    } else {
        $self->chat("Checksum for $file not found in CHECKSUMS.\n");
        return;
    }
}

sub sha_for {
    my($self, $alg, $file) = @_;

    require Digest::SHA; # no fatpack

    open my $fh, "<", $file or die "$file: $!";
    my $dg = Digest::SHA->new($alg);
    my($data);
    while (read($fh, $data, 4096)) {
        $dg->add($data);
    }

    return $dg->hexdigest;
}

sub verify_signature {
    my($self, $dist) = @_;

    $self->diag_progress("Verifying the SIGNATURE file");
    my $out = `@{[ qs $self->{cpansign} ]} -v --skip 2>&1`;
    $self->log($out);

    if ($out =~ /Signature verified OK/) {
        $self->diag_ok("Verified OK");
        return 1;
    } else {
        $self->diag_fail("SIGNATURE verification for $dist->{filename} failed\n");
        return;
    }
}

sub resolve_name {
    my($self, $module, $version, $dep) = @_;

    if ($dep && $dep->url) {
        if ($dep->url =~ m!authors/id/(.*)!) {
            return $self->cpan_dist($1, $dep->url);
        } else {
            return { uris => [ $dep->url ] };
        }
    }

    if ($dep && $dep->dist) {
        return $self->cpan_dist($dep->dist, undef, $dep->mirror);
    }

    # Git
    if ($module =~ /(?:^git:|\.git(?:@.+)?$)/) {
        return $self->git_uri($module);
    }

    # URL
    if ($module =~ /^(ftp|https?|file):/) {
        if ($module =~ m!authors/id/(.*)!) {
            return $self->cpan_dist($1, $module);
        } else {
            return { uris => [ $module ] };
        }
    }

    # Directory
    if ($module =~ m!^[\./]! && -d $module) {
        return {
            source => 'local',
            dir => Cwd::abs_path($module),
        };
    }

    # File
    if (-f $module) {
        return {
            source => 'local',
            uris => [ "file://" . Cwd::abs_path($module) ],
        };
    }

    # cpan URI
    if ($module =~ s!^cpan:///distfile/!!) {
        return $self->cpan_dist($module);
    }

    # PAUSEID/foo
    # P/PA/PAUSEID/foo
    if ($module =~ m!^(?:[A-Z]/[A-Z]{2}/)?([A-Z]{2}[\-A-Z0-9]*/.*)$!) {
        return $self->cpan_dist($1);
    }

    # Module name
    return $self->search_module($module, $version);
}

sub cpan_module_common {
    my($self, $match) = @_;

    (my $distfile = $match->{uri}) =~ s!^cpan:///distfile/!!;

    my $mirrors = $self->{mirrors};
    if ($match->{download_uri}) {
        (my $mirror = $match->{download_uri}) =~ s!/authors/id/.*$!!;
        $mirrors = [$mirror];
    }

    local $self->{mirrors} = $mirrors;
    return $self->cpan_module($match->{package}, $distfile, $match->{version});
}

sub cpan_module {
    my($self, $module, $dist_file, $version) = @_;

    my $dist = $self->cpan_dist($dist_file);
    $dist->{module} = $module;
    $dist->{module_version} = $version if $version && $version ne 'undef';

    return $dist;
}

sub cpan_dist {
    my($self, $dist, $url, $mirror) = @_;

    # strip trailing slash
    $mirror =~ s!/$!! if $mirror;

    $dist =~ s!^([A-Z]{2})!substr($1,0,1)."/".substr($1,0,2)."/".$1!e;

    require CPAN::DistnameInfo;
    my $d = CPAN::DistnameInfo->new($dist);

    if ($url) {
        $url = [ $url ] unless ref $url eq 'ARRAY';
    } else {
        my $id = $d->cpanid;
        my $fn = substr($id, 0, 1) . "/" . substr($id, 0, 2) . "/" . $id . "/" . $d->filename;

        my @mirrors = $mirror ? ($mirror) : @{$self->{mirrors}};
        my @urls    = map "$_/authors/id/$fn", @mirrors;

        $url = \@urls,
    }

    return {
        $d->properties,
        source  => 'cpan',
        uris    => $url,
    };
}

sub git_uri {
    my ($self, $uri) = @_;

    # similar to http://www.pip-installer.org/en/latest/logic.html#vcs-support
    # git URL has to end with .git when you need to use pin @ commit/tag/branch

    ($uri, my $commitish) = split /(?<=\.git)@/i, $uri, 2;

    my $dir = File::Temp::tempdir(CLEANUP => 1);

    $self->mask_output( diag_progress => "Cloning $uri" );
    $self->run_command([ 'git', 'clone', $uri, $dir ]);

    unless (-e "$dir/.git") {
        $self->diag_fail("Failed cloning git repository $uri", 1);
        return;
    }

    if ($commitish) {
        require File::pushd;
        my $dir = File::pushd::pushd($dir);

        unless ($self->run_command([ 'git', 'checkout', $commitish ])) {
            $self->diag_fail("Failed to checkout '$commitish' in git repository $uri\n");
            return;
        }
    }

    $self->diag_ok;

    return {
        source => 'local',
        dir    => $dir,
    };
}

sub core_version_for {
    my($self, $module) = @_;

    require Module::CoreList; # no fatpack
    unless (exists $Module::CoreList::version{$]+0}) {
        die sprintf("Module::CoreList %s (loaded from %s) doesn't seem to have entries for perl $]. " .
                    "You're strongly recommended to upgrade Module::CoreList from CPAN.\n",
                    $Module::CoreList::VERSION, $INC{"Module/CoreList.pm"});
    }

    unless (exists $Module::CoreList::version{$]+0}{$module}) {
        return -1;
    }

    return $Module::CoreList::version{$]+0}{$module};
}

sub search_inc {
    my $self = shift;
    $self->{search_inc} ||= do {
        # strip lib/ and fatlib/ from search path when booted from dev
        if (defined $::Bin) {
            [grep !/^\Q$::Bin\E\/..\/(?:fat)?lib$/, @INC]
        } else {
            [@INC]
        }
    };
}

sub check_module {
    my($self, $mod, $want_ver) = @_;

    require Module::Metadata;
    my $meta = Module::Metadata->new_from_module($mod, inc => $self->search_inc)
        or return 0, undef;

    my $version = $meta->version;

    # When -L is in use, the version loaded from 'perl' library path
    # might be newer than (or actually wasn't core at) the version
    # that is shipped with the current perl
    if ($self->{self_contained} && $self->loaded_from_perl_lib($meta)) {
        $version = $self->core_version_for($mod);
        return 0, undef if $version && $version == -1;
    }

    $self->{local_versions}{$mod} = $version;

    if ($self->is_deprecated($meta)){
        return 0, $version;
    } elsif ($self->satisfy_version($mod, $version, $want_ver)) {
        return 1, ($version || 'undef');
    } else {
        return 0, $version;
    }
}

sub satisfy_version {
    my($self, $mod, $version, $want_ver) = @_;

    $want_ver = '0' unless defined($want_ver) && length($want_ver);

    require CPAN::Meta::Requirements;
    my $requirements = CPAN::Meta::Requirements->new;
    $requirements->add_string_requirement($mod, $want_ver);
    $requirements->accepts_module($mod, $version);
}

sub unsatisfy_how {
    my($self, $ver, $want_ver) = @_;

    if ($want_ver =~ /^[v0-9\.\_]+$/) {
        return "$ver < $want_ver";
    } else {
        return "$ver doesn't satisfy $want_ver";
    }
}

sub is_deprecated {
    my($self, $meta) = @_;

    my $deprecated = eval {
        require Module::CoreList; # no fatpack
        Module::CoreList::is_deprecated($meta->{module});
    };

    return $deprecated && $self->loaded_from_perl_lib($meta);
}

sub loaded_from_perl_lib {
    my($self, $meta) = @_;

    require Config;
    my @dirs = qw(archlibexp privlibexp);
    if ($self->{self_contained} && ! $self->{exclude_vendor} && $Config{vendorarch}) {
        unshift @dirs, qw(vendorarch vendorlibexp);
    }
    for my $dir (@dirs) {
        my $confdir = $Config{$dir};
        if ($confdir eq substr($meta->filename, 0, length($confdir))) {
            return 1;
        }
    }

    return;
}

sub should_install {
    my($self, $mod, $ver) = @_;

    $self->chat("Checking if you have $mod $ver ... ");
    my($ok, $local) = $self->check_module($mod, $ver);

    if ($ok)       { $self->chat("Yes ($local)\n") }
    elsif ($local) { $self->chat("No (" . $self->unsatisfy_how($local, $ver) . ")\n") }
    else           { $self->chat("No\n") }

    return $mod unless $ok;
    return;
}

sub check_perl_version {
    my($self, $version) = @_;
    require CPAN::Meta::Requirements;
    my $req = CPAN::Meta::Requirements->from_string_hash({ perl => $version });
    $req->accepts_module(perl => $]);
}

sub install_deps {
    my($self, $dir, $depth, @deps) = @_;

    my(@install, %seen, @fail);
    for my $dep (@deps) {
        next if $seen{$dep->module};
        if ($dep->module eq 'perl') {
            if ($dep->is_requirement && !$self->check_perl_version($dep->version)) {
                $self->diag("Needs perl @{[$dep->version]}, you have $]\n");
                push @fail, 'perl';
            }
        } elsif ($self->should_install($dep->module, $dep->version)) {
            push @install, $dep;
            $seen{$dep->module} = 1;
        }
    }

    if (@install) {
        $self->diag("==> Found dependencies: " . join(", ",  map $_->module, @install) . "\n");
    }

    for my $dep (@install) {
        $self->install_module($dep->module, $depth + 1, $dep->version, $dep);
    }

    $self->chdir($self->{base});
    $self->chdir($dir) if $dir;

    if ($self->{scandeps}) {
        return 1; # Don't check if dependencies are installed, since with --scandeps they aren't
    }
    my @not_ok = $self->unsatisfied_deps(@deps);
    if (@not_ok) {
        return 0, \@not_ok;
    } else {
        return 1;
    }
}

sub unsatisfied_deps {
    my($self, @deps) = @_;

    require CPAN::Meta::Check;
    require CPAN::Meta::Requirements;

    my $reqs = CPAN::Meta::Requirements->new;
    for my $dep (grep $_->is_requirement, @deps) {
        $reqs->add_string_requirement($dep->module => $dep->requires_version || '0');
    }

    my $ret = CPAN::Meta::Check::check_requirements($reqs, 'requires', $self->{search_inc});
    grep defined, values %$ret;
}

sub install_deps_bailout {
    my($self, $target, $dir, $depth, @deps) = @_;

    my($ok, $fail) = $self->install_deps($dir, $depth, @deps);
    if (!$ok) {
        $self->diag_fail("Installing the dependencies failed: " . join(", ", @$fail), 1);
        unless ($self->prompt_bool("Do you want to continue building $target anyway?", "n")) {
            $self->diag_fail("Bailing out the installation for $target.", 1);
            return;
        }
    }

    return 1;
}

sub build_stuff {
    my($self, $stuff, $dist, $depth) = @_;

    if ($self->{verify} && -e 'SIGNATURE') {
        $self->verify_signature($dist) or return;
    }

    require CPAN::Meta;

    my($meta_file) = grep -f, qw(META.json META.yml);
    if ($meta_file) {
        $self->chat("Checking configure dependencies from $meta_file\n");
        $dist->{cpanmeta} = eval { CPAN::Meta->load_file($meta_file) };
    } elsif ($dist->{dist} && $dist->{version}) {
        $self->chat("META.yml/json not found. Creating skeleton for it.\n");
        $dist->{cpanmeta} = CPAN::Meta->new({ name => $dist->{dist}, version => $dist->{version} });
    }

    $dist->{meta} = $dist->{cpanmeta} ? $dist->{cpanmeta}->as_struct : {};

    if ($self->opts_in_static_install($dist->{cpanmeta})) {
        $dist->{static_install} = 1;
    }

    my @config_deps;

    if ($dist->{cpanmeta}) {
        push @config_deps, Menlo::Dependency->from_prereqs(
            $dist->{cpanmeta}->effective_prereqs, ['configure'], $self->{install_types},
        );
    }

    if (-e 'Build.PL' && !@config_deps) {
        push @config_deps, Menlo::Dependency->from_versions(
            { 'Module::Build' => '0.38' }, 'configure',
        );
    }

    $self->merge_with_cpanfile($dist, \@config_deps);

    $self->upgrade_toolchain(\@config_deps);

    my $target = $dist->{meta}{name} ? "$dist->{meta}{name}-$dist->{meta}{version}" : $dist->{dir};

    unless ($self->skip_configure($dist, $depth)) {
        $self->install_deps_bailout($target, $dist->{dir}, $depth, @config_deps)
          or return;
    }

    $self->diag_progress("Configuring $target");

    my $configure_state = $self->configure_this($dist, $depth);
    $self->diag_ok($configure_state->{configured_ok} ? "OK" : "N/A");

    if ($dist->{cpanmeta} && $dist->{source} eq 'cpan') {
        $dist->{provides} = $dist->{cpanmeta}{provides} || $self->extract_packages($dist->{cpanmeta}, ".");
    }

    # install direct 'test' dependencies for --installdeps, even with --notest
    # TODO: remove build dependencies for static install
    my $deps_only = $self->deps_only($depth);
    $dist->{want_phases} = $self->{notest} && !$self->deps_only($depth)
                         ? [qw( build runtime )] : [qw( build test runtime )];

    push @{$dist->{want_phases}}, 'develop' if $self->{with_develop} && $depth == 0;
    push @{$dist->{want_phases}}, 'configure' if $self->{with_configure} && $depth == 0;

    my @deps = $self->find_prereqs($dist);
    my $module_name = $self->find_module_name($configure_state) || $dist->{meta}{name};
    $module_name =~ s/-/::/g;

    if ($self->{showdeps}) {
        for my $dep (@config_deps, @deps) {
            print $dep->module, ($dep->version ? ("~".$dep->version) : ""), "\n";
        }
        return 1;
    }

    my $distname = $dist->{meta}{name} ? "$dist->{meta}{name}-$dist->{meta}{version}" : $stuff;

    my $walkup;
    if ($self->{scandeps}) {
        $walkup = $self->scandeps_append_child($dist);
    }

    $self->install_deps_bailout($distname, $dist->{dir}, $depth, @deps)
        or return;

    if ($self->{scandeps}) {
        unless ($configure_state->{configured_ok}) {
            my $diag = <<DIAG;
! Configuring $distname failed. See $self->{log} for details.
! You might have to install the following modules first to get --scandeps working correctly.
DIAG
            if (@config_deps) {
                my @tree = @{$self->{scandeps_tree}};
                $diag .= "!\n" . join("", map "! * $_->[0]{module}\n", @tree[0..$#tree-1]) if @tree;
            }
            $self->diag("!\n$diag!\n", 1);
        }
        $walkup->();
        return 1;
    }

    if ($self->{installdeps} && $depth == 0) {
        if ($configure_state->{configured_ok}) {
            $self->diag("<== Installed dependencies for $stuff. Finishing.\n");
            return 1;
        } else {
            $self->diag("! Configuring $distname failed. See $self->{log} for details.\n", 1);
            return;
        }
    }

    my $installed;
    if ($configure_state->{static_install}) {
        $self->diag_progress("Building " . ($self->{notest} ? "" : "and testing ") . $distname);
        $self->build(sub { $configure_state->{static_install}->build }, $distname, $dist, $depth) &&
        $self->test(sub { $configure_state->{static_install}->build("test") }, $distname, $dist, $depth) &&
        $self->install(sub { $configure_state->{static_install}->build("install") }, [], $dist, $depth) &&
        $installed++;
    } elsif ($configure_state->{use_module_build} && -e 'Build' && -f _) {
        $self->diag_progress("Building " . ($self->{notest} ? "" : "and testing ") . $distname);
        $self->build([ $self->{perl}, "./Build" ], $distname, $dist, $depth) &&
        $self->test([ $self->{perl}, "./Build", "test" ], $distname, $dist, $depth) &&
        $self->install([ $self->{perl}, "./Build", "install" ], [ "--uninst", 1 ], $dist, $depth) &&
        $installed++;
    } elsif ($self->{make} && -e 'Makefile') {
        $self->diag_progress("Building " . ($self->{notest} ? "" : "and testing ") . $distname);
        $self->build([ $self->{make} ], $distname, $dist, $depth) &&
        $self->test([ $self->{make}, "test" ], $distname, $dist, $depth) &&
        $self->install([ $self->{make}, "install" ], [ "UNINST=1" ], $dist, $depth) &&
        $installed++;
    } else {
        my $why;
        my $configure_failed = $configure_state->{configured} && !$configure_state->{configured_ok};
        if ($configure_failed) { $why = "Configure failed for $distname." }
        elsif ($self->{make})  { $why = "The distribution doesn't have a proper Makefile.PL/Build.PL" }
        else                   { $why = "Can't configure the distribution. You probably need to have 'make'." }

        $self->diag_fail("$why See $self->{log} for details.", 1);
        return;
    }

    if ($installed && $self->{test_only}) {
        $self->diag_ok;
        $self->diag("Successfully tested $distname\n", 1);
    } elsif ($installed) {
        my $local   = $self->{local_versions}{$dist->{module} || ''};
        my $version = $dist->{module_version} || $dist->{meta}{version} || $dist->{version};
        my $reinstall = $local && ($local eq $version);
        my $action  = $local && !$reinstall
                    ? $self->is_downgrade($version, $local)
                        ? "downgraded"
                        : "upgraded"
                    : undef;

        my $how = $reinstall ? "reinstalled $distname"
                : $local     ? "installed $distname ($action from $local)"
                             : "installed $distname" ;
        my $msg = "Successfully $how";
        $self->diag_ok;
        $self->diag("$msg\n", 1);
        $self->{installed_dists}++;
        $self->save_meta($stuff, $dist, $module_name, \@config_deps, \@deps);
        return 1;
    } else {
        my $what = $self->{test_only} ? "Testing" : "Installing";
        $self->diag_fail("$what $stuff failed. See $self->{log} for details. Retry with --force to force install it.", 1);
        return;
    }
}

sub is_downgrade {
    my($self, $va, $vb) = @_;
    eval { version::->new($va) < $vb };
}

sub opts_in_static_install {
    my($self, $meta) = @_;

    return if !$self->{static_install};

    # --sudo requires running a separate shell to prevent persistent configuration
    # uninstall-shadows (default on < 5.12) is not supported in BuildPL spec, yet.
    return if $self->{sudo} or $self->{uninstall_shadows};

    return $meta->{x_static_install} && $meta->{x_static_install} == 1;
}

sub skip_configure {
    my($self, $dist, $depth) = @_;

    return 1 if $self->{skip_configure};
    return 1 if $dist->{static_install};
    return 1 if $self->no_dynamic_config($dist->{meta}) && $self->deps_only($depth);

    return;
}

sub no_dynamic_config {
    my($self, $meta) = @_;
    exists $meta->{dynamic_config} && $meta->{dynamic_config} == 0;
}

sub deps_only {
    my($self, $depth) = @_;
    ($self->{installdeps} && $depth == 0)
      or $self->{showdeps}
      or $self->{scandeps};
}

sub perl_requirements {
    my($self, @requires) = @_;

    my @perl;
    for my $requires (grep defined, @requires) {
        if (exists $requires->{perl}) {
            push @perl, Menlo::Dependency->new(perl => $requires->{perl});
        }
    }

    return @perl;
}

sub configure_this {
    my($self, $dist, $depth) = @_;

    my $deps_only = $self->deps_only($depth);
    if (-e $self->{cpanfile_path} && $deps_only) {
        require Module::CPANfile;
        $dist->{cpanfile} = eval { Module::CPANfile->load($self->{cpanfile_path}) };
        $self->diag_fail($@, 1) if $@;

        $self->{cpanfile_global} ||= $dist->{cpanfile};

        return {
            configured       => 1,
            configured_ok    => !!$dist->{cpanfile},
            use_module_build => 0,
        };
    }

    if ($self->{skip_configure}) {
        my $eumm = -e 'Makefile';
        my $mb   = -e 'Build' && -f _;
        return {
            configured => 1,
            configured_ok => $eumm || $mb,
            use_module_build => $mb,
        };
    }

    if ($deps_only && $self->no_dynamic_config($dist->{meta})) {
        return {
            configured => 1,
            configured_ok => exists $dist->{meta}{prereqs},
            use_module_build => 0,
        };
    }

    my $state = {};

    my $try_static = sub {
        if ($dist->{static_install}) {
            $self->chat("Distribution opts in x_static_install: $dist->{meta}{x_static_install}\n");
            $self->static_install_configure($state, $dist, $depth);
        }
    };

    my $try_eumm = sub {
        if (-e 'Makefile.PL') {
            $self->chat("Running Makefile.PL\n");

            # NOTE: according to Devel::CheckLib, most XS modules exit
            # with 0 even if header files are missing, to avoid receiving
            # tons of FAIL reports in such cases. So exit code can't be
            # trusted if it went well.
            if ($self->configure([ $self->{perl}, "Makefile.PL" ], $dist, $depth)) {
                $state->{configured_ok} = -e 'Makefile';
            }
            $state->{configured}++;
        }
    };

    my $try_mb = sub {
        if (-e 'Build.PL') {
            $self->chat("Running Build.PL\n");
            if ($self->configure([ $self->{perl}, "Build.PL" ], $dist, $depth)) {
                $state->{configured_ok} = -e 'Build' && -f _;
            }
            $state->{use_module_build}++;
            $state->{configured}++;
        }
    };

    for my $try ($try_static, $try_mb, $try_eumm) {
        $try->();
        last if $state->{configured_ok};
    }

    unless ($state->{configured_ok}) {
        while (1) {
            my $ans = lc $self->prompt("Configuring $dist->{dist} failed.\nYou can s)kip, r)etry, e)xamine build log, or l)ook ?", "s");
            last                                        if $ans eq 's';
            return $self->configure_this($dist, $depth) if $ans eq 'r';
            $self->show_build_log                       if $ans eq 'e';
            $self->look                                 if $ans eq 'l';
        }
    }

    return $state;
}

sub static_install_configure {
    my($self, $state, $dist, $depth) = @_;

    my $args = $depth == 0 ? $self->{build_args}{configure} : [];

    require Menlo::Builder::Static;
    my $builder = Menlo::Builder::Static->new(meta => $dist->{cpanmeta});
    $self->configure(sub { $builder->configure($args || []) }, $dist, $depth);

    $state->{configured_ok} = 1;
    $state->{static_install} = $builder;
    $state->{configured}++;
}

sub find_module_name {
    my($self, $state) = @_;

    return unless $state->{configured_ok};

    if ($state->{use_module_build} &&
        -e "_build/build_params") {
        my $params = do { open my $in, "_build/build_params"; eval(join "", <$in>) };
        return eval { $params->[2]{module_name} } || undef;
    } elsif (-e "Makefile") {
        open my $mf, "Makefile";
        while (<$mf>) {
            if (/^\#\s+NAME\s+=>\s+(.*)/) {
                return eval($1);
            }
        }
    }

    return;
}

sub list_files {
    my $self = shift;

    if (-e 'MANIFEST') {
        require ExtUtils::Manifest;
        my $manifest = eval { ExtUtils::Manifest::manifind() } || {};
        return sort { lc $a cmp lc $b } keys %$manifest;
    } else {
        require File::Find;
        my @files;
        my $finder = sub {
            my $name = $File::Find::name;
            $name =~ s!\.[/\\]!!;
            push @files, $name;
        };
        File::Find::find($finder, ".");
        return sort { lc $a cmp lc $b } @files;
    }
}

sub extract_packages {
    my($self, $meta, $dir) = @_;

    my $try = sub {
        my $file = shift;
        return 0 if $file =~ m!^(?:x?t|inc|local|perl5|fatlib|_build)/!;
        return 1 unless $meta->{no_index};
        return 0 if grep { $file =~ m!^$_/! } @{$meta->{no_index}{directory} || []};
        return 0 if grep { $file eq $_ } @{$meta->{no_index}{file} || []};
        return 1;
    };

    require Parse::PMFile;

    my @files = grep { /\.pm(?:\.PL)?$/ && $try->($_) } $self->list_files;

    my $provides = { };

    for my $file (@files) {
        my $parser = Parse::PMFile->new($meta, { UNSAFE => 1, ALLOW_DEV_VERSION => 1 });
        my $packages = $parser->parse($file);

        while (my($package, $meta) = each %$packages) {
            $provides->{$package} ||= {
                file => $meta->{infile},
                ($meta->{version} eq 'undef') ? () : (version => $meta->{version}),
            };
        }
    }

    return $provides;
}

sub save_meta {
    my($self, $module, $dist, $module_name, $config_deps, $build_deps) = @_;

    return unless $dist->{distvname} && $dist->{source} eq 'cpan';

    my $base = ($ENV{PERL_MM_OPT} || '') =~ /INSTALL_BASE=/
        ? ($self->install_base($ENV{PERL_MM_OPT}) . "/lib/perl5") : $Config{sitelibexp};

    my $provides = $dist->{provides};

    File::Path::mkpath("blib/meta", 0, 0777);

    my $local = {
        name => $module_name,
        target => $module,
        version => exists $provides->{$module_name}
            ? ($provides->{$module_name}{version} || $dist->{version}) : $dist->{version},
        dist => $dist->{distvname},
        pathname => $dist->{pathname},
        provides => $provides,
    };

    require JSON::PP;
    open my $fh, ">", "blib/meta/install.json" or die $!;
    print $fh JSON::PP::encode_json($local);

    File::Copy::copy("MYMETA.json", "blib/meta/MYMETA.json");

    my @cmd = (
        ($self->{sudo} ? 'sudo' : ()),
        $^X,
        '-MExtUtils::Install=install',
        '-e',
        qq[install({ 'blib/meta' => '$base/$Config{archname}/.meta/$dist->{distvname}' })],
    );
    $self->run_command(\@cmd);
}

sub install_base {
    my($self, $mm_opt) = @_;
    $mm_opt =~ /INSTALL_BASE=(\S+)/ and return $1;
    die "Your PERL_MM_OPT doesn't contain INSTALL_BASE";
}

sub configure_features {
    my($self, $dist, @features) = @_;
    map $_->identifier, grep { $self->effective_feature($dist, $_) } @features;
}

sub effective_feature {
    my($self, $dist, $feature) = @_;

    if ($dist->{depth} == 0) {
        my $value = $self->{features}{$feature->identifier};
        return $value if defined $value;
        return 1 if $self->{features}{__all};
    }

    if ($self->{interactive}) {
        require CPAN::Meta::Requirements;

        $self->diag("[@{[ $feature->description ]}]\n", 1);

        my $req = CPAN::Meta::Requirements->new;
        for my $phase (@{$dist->{want_phases}}) {
            for my $type (@{$self->{install_types}}) {
                $req->add_requirements($feature->prereqs->requirements_for($phase, $type));
            }
        }

        my $reqs = $req->as_string_hash;
        my @missing;
        for my $module (keys %$reqs) {
            if ($self->should_install($module, $req->{$module})) {
                push @missing, $module;
            }
        }

        if (@missing) {
            my $howmany = @missing;
            $self->diag("==> Found missing dependencies: " . join(", ", @missing) . "\n", 1);
            local $self->{prompt} = 1;
            return $self->prompt_bool("Install the $howmany optional module(s)?", "y");
        }
    }

    return;
}

sub find_prereqs {
    my($self, $dist) = @_;

    my @deps = $self->extract_meta_prereqs($dist);

    if ($dist->{module} =~ /^Bundle::/i) {
        push @deps, $self->bundle_deps($dist);
    }

    $self->merge_with_cpanfile($dist, \@deps);

    return @deps;
}

sub merge_with_cpanfile {
    my($self, $dist, $deps) = @_;

    if ($self->{cpanfile_requirements} && !$dist->{cpanfile}) {
        for my $dep (@$deps) {
            $dep->merge_with($self->{cpanfile_requirements});
        }
    }

    if ($self->{cpanfile_global}) {
        for my $dep (@$deps) {
            my $opts = $self->{cpanfile_global}->options_for_module($dep->module)
              or next;

            $dep->dist($opts->{dist})     if $opts->{dist};
            $dep->mirror($opts->{mirror}) if $opts->{mirror};
            $dep->url($opts->{url})       if $opts->{url};
        }
    }
}

sub extract_meta_prereqs {
    my($self, $dist) = @_;

    if ($dist->{cpanfile}) {
        my @features = $self->configure_features($dist, $dist->{cpanfile}->features);
        my $prereqs = $dist->{cpanfile}->prereqs_with(@features);
        # TODO: creating requirements is useful even without cpanfile to detect conflicting prereqs
        $self->{cpanfile_requirements} = $prereqs->merged_requirements($dist->{want_phases}, ['requires']);
        return Menlo::Dependency->from_prereqs($prereqs, $dist->{want_phases}, $self->{install_types});
    }

    require CPAN::Meta;

    my @meta = qw(MYMETA.json MYMETA.yml);
    if ($self->no_dynamic_config($dist->{meta})) {
        push @meta, qw(META.json META.yml);
    }

    my @deps;
    my($meta_file) = grep -f, @meta;
    if ($meta_file) {
        $self->chat("Checking dependencies from $meta_file ...\n");
        my $mymeta = eval { CPAN::Meta->load_file($meta_file, { lazy_validation => 1 }) };
        if ($mymeta) {
            $dist->{meta}{name}    = $mymeta->name;
            $dist->{meta}{version} = $mymeta->version;
            return $self->extract_prereqs($mymeta, $dist);
        }
    }

    $self->diag_fail("No MYMETA file is found after configure. Your toolchain is too old?");
    return;
}

sub bundle_deps {
    my($self, $dist) = @_;

    my $match;
    if ($dist->{module}) {
        $match = sub {
            my $meta = Module::Metadata->new_from_file($_[0]);
            $meta && ($meta->name eq $dist->{module});
        };
    } else {
        $match = sub { 1 };
    }

    my @files;
    File::Find::find({
        wanted => sub {
            push @files, File::Spec->rel2abs($_) if /\.pm$/i && $match->($_);
        },
        no_chdir => 1,
    }, '.');

    my @deps;

    for my $file (@files) {
        open my $pod, "<", $file or next;
        my $in_contents;
        while (<$pod>) {
            if (/^=head\d\s+CONTENTS/) {
                $in_contents = 1;
            } elsif (/^=/) {
                $in_contents = 0;
            } elsif ($in_contents) {
                /^(\S+)\s*(\S+)?/
                    and push @deps, Menlo::Dependency->new($1, $self->maybe_version($2));
            }
        }
    }

    return @deps;
}

sub maybe_version {
    my($self, $string) = @_;
    return $string && $string =~ /^\.?\d/ ? $string : undef;
}

sub extract_prereqs {
    my($self, $meta, $dist) = @_;

    my @features = $self->configure_features($dist, $meta->features);

    my $prereqs = $meta->effective_prereqs(\@features)->clone;
    $self->adjust_prereqs($dist, $prereqs);

    return Menlo::Dependency->from_prereqs($prereqs, $dist->{want_phases}, $self->{install_types});
}

sub adjust_prereqs {
    my($self, $dist, $prereqs) = @_;

    # Workaround for Module::Install 1.04 creating a bogus (higher) MakeMaker requirement that it needs in build_requires
    # Assuming MakeMaker requirement is already satisfied in configure_requires, there's no need to have higher version of
    # MakeMaker in build/test anyway. https://github.com/miyagawa/cpanminus/issues/463
    if (-e "inc/Module/Install.pm") {
        for my $phase (qw( build test runtime )) {
            my $reqs = $prereqs->requirements_for($phase, 'requires');
            if ($reqs->requirements_for_module('ExtUtils::MakeMaker')) {
                $reqs->clear_requirement('ExtUtils::MakeMaker');
                $reqs->add_minimum('ExtUtils::MakeMaker' => 0);
            }
        }
    }

    # Static installation is optional and we're adding runtime dependencies
    if ($dist->{static_install}) {
        my $reqs = $prereqs->requirements_for('test' => 'requires');
        $reqs->add_minimum('TAP::Harness::Env' => 0);
    }
}

sub cleanup_workdirs {
    my $self = shift;

    my $expire = time - 24 * 60 * 60 * $self->{auto_cleanup};
    my @targets;

    opendir my $dh, "$self->{home}/work";
    while (my $e = readdir $dh) {
        next if $e !~ /^(\d+)\.\d+$/; # {UNIX time}.{PID}
        my $time = $1;
        if ($time < $expire) {
            push @targets, "$self->{home}/work/$e";
        }
    }

    if (@targets) {
        if (@targets >= 64) {
            $self->diag("Expiring " . scalar(@targets) . " work directories. This might take a while...\n");
        } else {
            $self->chat("Expiring " . scalar(@targets) . " work directories.\n");
        }
        File::Path::rmtree(\@targets, 0, 0); # safe = 0, since blib usually doesn't have write bits
    }
}

sub scandeps_append_child {
    my($self, $dist) = @_;

    my $new_node = [ $dist, [] ];

    my $curr_node = $self->{scandeps_current} || [ undef, $self->{scandeps_tree} ];
    push @{$curr_node->[1]}, $new_node;

    $self->{scandeps_current} = $new_node;

    return sub { $self->{scandeps_current} = $curr_node };
}

sub dump_scandeps {
    my $self = shift;

    if ($self->{format} eq 'tree') {
        $self->walk_down(sub {
            my($dist, $depth) = @_;
            if ($depth == 0) {
                print "$dist->{distvname}\n";
            } else {
                print " " x ($depth - 1);
                print "\\_ $dist->{distvname}\n";
            }
        }, 1);
    } elsif ($self->{format} =~ /^dists?$/) {
        $self->walk_down(sub {
            my($dist, $depth) = @_;
            print $self->format_dist($dist), "\n";
        }, 0);
    } elsif ($self->{format} eq 'json') {
        require JSON::PP;
        print JSON::PP::encode_json($self->{scandeps_tree});
    } elsif ($self->{format} eq 'yaml') {
        require CPAN::Meta::YAML;
        print CPAN::Meta::YAML::Dump($self->{scandeps_tree});
    } else {
        $self->diag("Unknown format: $self->{format}\n");
    }
}

sub walk_down {
    my($self, $cb, $pre) = @_;
    $self->_do_walk_down($self->{scandeps_tree}, $cb, 0, $pre);
}

sub _do_walk_down {
    my($self, $children, $cb, $depth, $pre) = @_;

    # DFS - $pre determines when we call the callback
    for my $node (@$children) {
        $cb->($node->[0], $depth) if $pre;
        $self->_do_walk_down($node->[1], $cb, $depth + 1, $pre);
        $cb->($node->[0], $depth) unless $pre;
    }
}

sub DESTROY {
    my $self = shift;
    $self->{at_exit}->($self) if $self->{at_exit};
}

# Utils

sub mirror {
    my($self, $uri, $local) = @_;
    if ($uri =~ /^file:/) {
        $self->file_mirror($uri, $local);
    } else {
        $self->{http}->mirror($uri, $local);
    }
}

sub untar    { $_[0]->{_backends}{untar}->(@_) };
sub unzip    { $_[0]->{_backends}{unzip}->(@_) };

sub uri_to_file {
    my($self, $uri) = @_;

    # file:///path/to/file -> /path/to/file
    # file://C:/path       -> C:/path
    if ($uri =~ s!file:/+!!) {
        $uri = "/$uri" unless $uri =~ m![a-zA-Z]:!;
    }

    return $uri;
}

sub file_get {
    my($self, $uri) = @_;
    my $file = $self->uri_to_file($uri);
    open my $fh, "<$file" or return;
    join '', <$fh>;
}

sub file_mirror {
    my($self, $uri, $path) = @_;
    my $file = $self->uri_to_file($uri);

    my $source_mtime = (stat $file)[9];

    # Don't mirror a file that's already there (like the index)
    return 1 if -e $path && (stat $path)[9] >= $source_mtime;

    File::Copy::copy($file, $path);

    utime $source_mtime, $source_mtime, $path;
}

sub configure_http {
    my $self = shift;

    require HTTP::Tinyish;

    my @try = qw(HTTPTiny);
    unshift @try, 'Wget' if $self->{try_wget};
    unshift @try, 'Curl' if $self->{try_curl};
    unshift @try, 'LWP'  if $self->{try_lwp};

    my @protocol = ('http');
    push @protocol, 'https'
      if grep /^https:/, @{$self->{mirrors}};

    my $backend;
    for my $try (map "HTTP::Tinyish::$_", @try) {
        if (my $meta = HTTP::Tinyish->configure_backend($try)) {
            if ((grep $try->supports($_), @protocol) == @protocol) {
                for my $tool (sort keys %$meta){
                    (my $desc = $meta->{$tool}) =~ s/^(.*?)\n.*/$1/s;
                    $self->chat("You have $tool: $desc\n");
                }
                $backend = $try;
                last;
            }
        }
    }

    $backend->new(agent => "Menlo/$Menlo::VERSION", verify_SSL => 1);
}

sub init_tools {
    my $self = shift;

    return if $self->{initialized}++;

    if ($self->{make} = which($Config{make})) {
        $self->chat("You have make $self->{make}\n");
    }

    $self->{http} = $self->configure_http;

    my $tar = which('tar');
    my $tar_ver;
    my $maybe_bad_tar = sub { WIN32 || BAD_TAR || (($tar_ver = `@{[ qs $tar ]} --version 2>/dev/null`) =~ /GNU.*1\.13/i) };

    if ($tar && !$maybe_bad_tar->()) {
        chomp $tar_ver;
        $self->chat("You have $tar: $tar_ver\n");
        $self->{_backends}{untar} = sub {
            my($self, $tarfile) = @_;

            my $xf = ($self->{verbose} ? 'v' : '')."xf";
            my $ar = $tarfile =~ /bz2$/ ? 'j' : 'z';

            my($root, @others) = `@{[ qs $tar ]} ${ar}tf @{[ qs $tarfile ]}`
                or return undef;

            FILE: {
                chomp $root;
                $root =~ s!^\./!!;
                $root =~ s{^(.+?)/.*$}{$1};

                if (!length($root)) {
                    # archive had ./ as the first entry, so try again
                    $root = shift(@others);
                    redo FILE if $root;
                }
            }

            $self->run_command([ $tar, $ar.$xf, $tarfile ]);
            return $root if -d $root;

            $self->diag_fail("Bad archive: $tarfile");
            return undef;
        }
    } elsif (    $tar
             and my $gzip = which('gzip')
             and my $bzip2 = which('bzip2')) {
        $self->chat("You have $tar, $gzip and $bzip2\n");
        $self->{_backends}{untar} = sub {
            my($self, $tarfile) = @_;

            my $x  = "x" . ($self->{verbose} ? 'v' : '') . "f -";
            my $ar = $tarfile =~ /bz2$/ ? $bzip2 : $gzip;

            my($root, @others) = `@{[ qs $ar ]} -dc @{[ qs $tarfile ]} | @{[ qs $tar ]} tf -`
                or return undef;

            FILE: {
                chomp $root;
                $root =~ s!^\./!!;
                $root =~ s{^(.+?)/.*$}{$1};

                if (!length($root)) {
                    # archive had ./ as the first entry, so try again
                    $root = shift(@others);
                    redo FILE if $root;
                }
            }

            system "@{[ qs $ar ]} -dc @{[ qs $tarfile ]} | @{[ qs $tar ]} $x";
            return $root if -d $root;

            $self->diag_fail("Bad archive: $tarfile");
            return undef;
        }
    } elsif (eval { require Archive::Tar }) { # uses too much memory!
        $self->chat("Falling back to Archive::Tar $Archive::Tar::VERSION\n");
        $self->{_backends}{untar} = sub {
            my $self = shift;
            my $t = Archive::Tar->new($_[0]);
            my($root, @others) = $t->list_files;
            FILE: {
                $root =~ s!^\./!!;
                $root =~ s{^(.+?)/.*$}{$1};

                if (!length($root)) {
                    # archive had ./ as the first entry, so try again
                    $root = shift(@others);
                    redo FILE if $root;
                }
            }
            $t->extract;
            return -d $root ? $root : undef;
        };
    } else {
        $self->{_backends}{untar} = sub {
            die "Failed to extract $_[1] - You need to have tar or Archive::Tar installed.\n";
        };
    }

    if (my $unzip = which('unzip')) {
        $self->chat("You have $unzip\n");
        $self->{_backends}{unzip} = sub {
            my($self, $zipfile) = @_;

            my @opt = $self->{verbose} ? () : ('-q');
            my(undef, $root, @others) = `@{[ qs $unzip ]} -t @{[ qs $zipfile ]}`
                or return undef;
            FILE: {
                chomp $root;
                if ($root !~ s{^\s+testing:\s+([^/]+)/.*?\s+OK$}{$1}) {
                    $root = shift(@others);
                    redo FILE if $root;
                }
            }

            $self->run_command([ $unzip, @opt, $zipfile ]);
            return $root if -d $root;

            $self->diag_fail("Bad archive: '$root' $zipfile");
            return undef;
        }
    } else {
        $self->{_backends}{unzip} = sub {
            eval { require Archive::Zip }
                or  die "Failed to extract $_[1] - You need to have unzip or Archive::Zip installed.\n";
            my($self, $file) = @_;
            my $zip = Archive::Zip->new();
            my $status;
            $status = $zip->read($file);
            $self->diag_fail("Read of file '$file' failed")
                if $status != Archive::Zip::AZ_OK();
            my @members = $zip->members();
            for my $member ( @members ) {
                my $af = $member->fileName();
                next if ($af =~ m!^(/|\.\./)!);
                $status = $member->extractToFileNamed( $af );
                $self->diag_fail("Extracting of file 'af' from zipfile '$file' failed")
                    if $status != Archive::Zip::AZ_OK();
            }

            my ($root) = $zip->membersMatching( qr<^[^/]+/$> );
            $root &&= $root->fileName;
            return -d $root ? $root : undef;
        };
    }
}

sub mask_uri_passwords {
    my($self, @strings) = @_;
    s{ (https?://) ([^:/]+) : [^@/]+ @ }{$1$2:********@}gx for @strings;
    return @strings;
}

1;

__END__

=encoding utf-8

=head1 NAME

Menlo::CLI::Compat - cpanm compatible CPAN installer

=head1 SYNOPSIS

  use Menlo::CLI::Compat;

  my $app = Menlo::CLI::Compat->new;
  $app->parse_options(@ARGV);
  $app->run;

=head1 DESCRIPTION

Menlo::CLI::Compat is a port of App::cpanminus to Menlo, and provides
a compatibility layer for users and clients to depend on the specific
cpanm behaviors.

=head1 SEE ALSO

L<Menlo>, L<Menlo::Legacy>

=cut

