#!/usr/bin/perl
use 5.10.1;
use strict;
use warnings;
use lib qw(/app /app/local/lib/perl5);
use Bugzilla::Install::Localconfig ();
use Bugzilla::Install::Util qw(install_string);
use DBI;
use Data::Dumper;
use English qw($EUID);
use File::Copy::Recursive qw(dircopy);
use Getopt::Long qw(:config gnu_getopt);
use LWP::Simple qw(get);
use User::pwent;
use POSIX qw(WEXITSTATUS setsid);

use IO::Async::Loop;
use IO::Async::Process;
use IO::Async::Timer::Periodic;
use IO::Async::Signal;

use constant CI => $ENV{CI};

my $cmd = shift @ARGV;
my $func = __PACKAGE__->can("cmd_$cmd")
    or die "unknown command: $cmd\n";
my $opts = __PACKAGE__->can("opt_$cmd") // sub { @ARGV };

fix_path();
check_user();
check_env() unless $cmd eq 'shell';
write_localconfig( localconfig_from_env() );

$func->(@ARGV);

sub cmd_httpd  {
    check_data_dir();
    wait_for_db();

}

sub cmd_load_test_data {
    wait_for_db();

    die "BZ_QA_ANSWERS_FILE is not set" unless $ENV{BZ_QA_ANSWERS_FILE};
    run( 'perl', 'checksetup.pl', '--no-template', $ENV{BZ_QA_ANSWERS_FILE} );

    if ($ENV{BZ_QA_LEGACY_MODE}) {
        run( 'perl', 'scripts/generate_bmo_data.pl',
            '--user-pref', 'ui_experiments=off' );
        chdir '/app/qa/config';
        say 'chdir(/app/qa/config)';
        run( 'perl', 'generate_test_data.pl' );
    }
    else {
        run( 'perl', 'scripts/generate_bmo_data.pl' );
    }
}

sub cmd_test_heartbeat {
    my ($url) = @_;
    die "test_heartbeat requires a url!\n" unless $url;

    wait_for_httpd($url);
    my $heartbeat = get("$url/__heartbeat__");
    if ($heartbeat && $heartbeat =~ /Bugzilla OK/) {
        exit 0;
    }
    else {
        exit 1;
    }
}

sub cmd_test_webservices {

    my $conf = require $ENV{BZ_QA_CONF_FILE};

    check_data_dir();
    my @httpd_cmd = ( '/usr/sbin/httpd', '-DFOREGROUND', '-f', '/app/httpd/httpd.conf' );
    if ($ENV{BZ_QA_LEGACY_MODE}) {
        copy_qa_extension();
        push @httpd_cmd, '-DHTTPD_IN_SUBDIR';
    }

    prove_with_httpd(
        httpd_url => $conf->{browser_url},
        httpd_cmd => \@httpd_cmd,
        prove_cmd => [
            'prove', '-qf', '-I/app',
            '-I/app/local/lib/perl5',
            sub { glob('webservice_*.t') },
        ],
        prove_dir => '/app/qa/t',
    );
}

sub cmd_test_selenium {
    my $conf = require $ENV{BZ_QA_CONF_FILE};

    check_data_dir();
    my @httpd_cmd = ( '/usr/sbin/httpd', '-DFOREGROUND', '-f', '/app/httpd/httpd.conf' );
    if ($ENV{BZ_QA_LEGACY_MODE}) {
        copy_qa_extension();
        push @httpd_cmd, '-DHTTPD_IN_SUBDIR';
    }

    prove_with_httpd(
        httpd_url => $conf->{browser_url},
        httpd_cmd => \@httpd_cmd,
        prove_cmd => [
            'prove', '-qf', '-Ilib', '-I/app',
            '-I/app/local/lib/perl5',
            sub { glob('test_*.t') }
        ],
        prove_dir => '/app/qa/t',
    );
}

sub cmd_shell   { run( 'bash',  '-l' ); }
sub cmd_prove   { run( "prove", "-I/app", "-I/app/local/lib/perl5", @_ ); }
sub cmd_version { run( 'cat',   '/app/version.json' ); }

sub cmd_test_bmo {
    prove_with_httpd(
        httpd_url => $ENV{BZ_BASE_URL},
        httpd_cmd => [ '/usr/sbin/httpd', '-f', '/app/httpd/httpd.conf',  '-DFOREGROUND' ],
        prove_cmd => [ "prove", "-I/app", "-I/app/local/lib/perl5", @_ ],
    );
}

sub prove_with_httpd {
    my (%param) = @_;

    check_data_dir();
    wait_for_db();

    unless (-d "/app/logs") {
        mkdir("/app/logs") or die "unable to mkdir(/app/logs): $!\n";
    }

    my $httpd_cmd = $param{httpd_cmd};
    my $prove_cmd = $param{prove_cmd};

    my $loop = IO::Async::Loop->new;

    my $httpd_exit_f = $loop->new_future;
    warn "starting httpd\n";
    my $httpd = IO::Async::Process->new(
        code => sub {
            setsid();
            exec(@$httpd_cmd);
        },
        setup => [
             stdout => ["open", ">", "/app/logs/access.log"],
             stderr => ["open", ">", "/app/logs/error.log"],
        ],
        on_finish => on_finish($httpd_exit_f),
        on_exception => on_exception('httpd', $httpd_exit_f),
    );
    $loop->add($httpd);
    wait_for_httpd( $httpd, $param{httpd_url} );

    warn "httpd started, starting prove\n";

    my $prove_exit_f = $loop->new_future;
    my $prove = IO::Async::Process->new(
        code => sub {
            chdir($param{prove_dir}) if $param{prove_dir};
            my @cmd = (map { ref $_ eq 'CODE' ? $_->() : $_ } @$prove_cmd);
            warn "run @cmd\n";
            exec(@cmd);
        },
        on_finish    => on_finish($prove_exit_f),
        on_exception => on_exception('prove', $prove_exit_f),
    );
    $loop->add($prove);

    my $prove_exit = $prove_exit_f->get();
    if ($httpd->is_running) {
        $httpd->kill('TERM');
        my $httpd_exit = $httpd_exit_f->get();
        warn "httpd exit code: $httpd_exit\n" if $httpd_exit != 0;
    }

    exit $prove_exit;
}

sub wait_for_httpd {
    my ($process, $url) = @_;
    my $loop = IO::Async::Loop->new;
    my $is_running_f = $loop->new_future;
    my $ticks = 0;
    my $run_checker = IO::Async::Timer::Periodic->new(
        first_interval => 0,
        interval       => 1,
        reschedule     => 'hard',
        on_tick        => sub {
            my ($timer) = @_;
            if ( $process->is_running ) {
                my $resp = get("$url/__lbheartbeat__");
                if ($resp && $resp =~ /^httpd OK$/) {
                    $timer->stop;
                    $is_running_f->done($resp);
                }
                say "httpd doesn't seem to be up at $url. waiting...";
            }
            elsif ( $process->is_exited ) {
                $timer->stop;
                $is_running_f->fail("process exited early");
            }
            elsif ( $ticks++ > 60 ) {
                $timer->stop;
                $is_running_f->fail("is_running_future() timeout after $ticks seconds");
            }
            $timer->stop if $ticks++ > 60;
        },
    );
    $loop->add($run_checker->start);
    return $is_running_f->get();
}

sub copy_qa_extension {
    say "copying the QA extension...";
    dircopy('/app/qa/extensions/QA', '/app/extensions/QA');
}

sub wait_for_db {
    my $c = Bugzilla::Install::Localconfig::read_localconfig();
    for my $var (qw(db_name db_host db_user db_pass)) {
        die "$var is not set!" unless $c->{$var};
    }

    my $dsn = "dbi:mysql:database=$c->{db_name};host=$c->{db_host}";
    my $dbh;
    foreach (1..12) {
        say "checking database..." if $_ > 1;
        $dbh = DBI->connect(
            $dsn,
            $c->{db_user},
            $c->{db_pass}, 
            { RaiseError => 0, PrintError => 0 }
        );
        last if $dbh;
        say "database $dsn not available, waiting...";
        sleep(10);
    }
    die "unable to connect to $dsn as $c->{db_user}\n" unless $dbh;
}

sub on_exception {
    my ($name, $f) = @_;
    return sub {
        my ( $self, $exception, $errno, $exitcode ) = @_;

        if ( length $exception ) {
            $f->fail("$name died with the exception $exception " . "(errno was $errno)\n");
        }
        elsif ( ( my $status = WEXITSTATUS($exitcode) ) == 255 ) {
            $f->fail("$name failed to exec() - $errno\n");
        }
        else {
            $f->fail("$name exited with exit status $status\n");
        }
    };
}

sub on_finish {
    my ($f) = @_;
    return sub {
        my ($self, $exitcode) = @_;
        $f->done(WEXITSTATUS($exitcode));
    };
}

sub localconfig_from_env {
    my %localconfig = ( webservergroup => 'app' );

    my %override = (
        'inbound_proxies' => 1,
        'shadowdb'        => 1,
        'shadowdbhost'    => 1,
        'shadowdbport'    => 1,
        'shadowdbsock'    => 1
    );

    foreach my $key ( keys %ENV ) {
        if ( $key =~ /^BMO_(.+)$/ ) {
            my $name = $1;
            if ( $override{$name} ) {
                $localconfig{param_override}{$name} = delete $ENV{$key};
            }
            else {
                $localconfig{$name} = delete $ENV{$key};
            }
        }
    }

    return \%localconfig;
}

sub write_localconfig {
    my ($localconfig) = @_;
    no warnings 'once';

    my $filename = "/app/localconfig";

    die "/app/localconfig already exists!" if -f $filename;

    foreach my $var (Bugzilla::Install::Localconfig::LOCALCONFIG_VARS) {
        my $name = $var->{name};
        my $value = $localconfig->{$name};
        if (!defined $value) {
            $var->{default} = &{$var->{default}} if ref($var->{default}) eq 'CODE';
            $localconfig->{$name} = $var->{default};
        }
    }

    # Ensure output is sorted and deterministic
    local $Data::Dumper::Sortkeys = 1;

    # Re-write localconfig
    open my $fh, ">:utf8", $filename or die "$filename: $!";
    foreach my $var (Bugzilla::Install::Localconfig::LOCALCONFIG_VARS) {
        my $name = $var->{name};
        my $desc = install_string("localconfig_$name", { root => Bugzilla::Install::Localconfig::ROOT_USER });
        chomp($desc);
        # Make the description into a comment.
        $desc =~ s/^/# /mg;
        print $fh $desc, "\n",
                  Data::Dumper->Dump([$localconfig->{$name}],
                                     ["*$name"]), "\n";
   }
   close $fh;
}

sub check_user {
    die "Effective UID must be 10001!" unless $EUID == 10001;
    my $user = getpwuid($EUID)->name;
    die "Name of EUID must be app, not $user" unless $user eq 'app';
}

sub check_data_dir {
    die "/app/data must be writable by user 'app' (id: $EUID)" unless -w "/app/data";
    die "/app/data/params must exist" unless -f "/app/data/params";
}

sub check_env {
    my @require_env = qw(
        BMO_db_host
        BMO_db_name
        BMO_db_user
        BMO_db_pass
        BMO_memcached_namespace
        BMO_memcached_servers
    );
    my @missing_env = grep { not exists $ENV{$_} } @require_env;
    if (@missing_env) {
        die "Missing required environmental variables: ", join(", ", @missing_env), "\n";
    }
}

sub fix_path {
    $ENV{PATH} = "/app/local/bin:$ENV{PATH}";
}

sub run {
    my (@cmd) = @_;
    say "+ @cmd";
    my $rv = system(@cmd);
    if ($rv != 0) {
        exit 1;
    }
}
