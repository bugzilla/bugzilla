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

my $cmd = shift @ARGV;
my $func = __PACKAGE__->can("cmd_$cmd") // sub { run($cmd, @ARGV) };

fix_path();
check_user();
check_env() unless $cmd eq 'shell';
write_localconfig( localconfig_from_env() );
$func->(@ARGV);

sub cmd_httpd  {
    check_data_dir();
    wait_for_db();
    run( '/usr/sbin/httpd', '-DFOREGROUND', 
        '-f', '/app/httpd/httpd.conf', @_ );
}

sub cmd_qa_httpd {
    copy_qa_extension();
    cmd_httpd('-DHTTPD_IN_SUBDIR', @_);
}

sub cmd_load_test_data {
    wait_for_db();

    die "BZ_QA_ANSWERS_FILE is not set" unless $ENV{BZ_QA_ANSWERS_FILE};
    run( 'perl', 'checksetup.pl', '--no-template', $ENV{BZ_QA_ANSWERS_FILE} );
    run( 'perl', 'scripts/generate_bmo_data.pl',
        '--user-pref', 'ui_experiments=off' );
    chdir '/app/qa/config';
    say 'chdir(/app/qa/config)';
    run( 'perl', 'generate_test_data.pl' );
}

sub cmd_test_heartbeat {
    my $conf = require $ENV{BZ_QA_CONF_FILE};
    wait_for_httpd($conf->{browser_url});
    my $heartbeat = get("$conf->{browser_url}/__heartbeat__");
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
    wait_for_db();
    wait_for_httpd($conf->{browser_url});
    copy_qa_extension();

    chdir('/app/qa/t');
    run( 'prove', '-qf', '-I/app', '-I/app/local/lib/perl5', glob('webservice_*.t') );
}

sub cmd_test_selenium {
    my $conf = require $ENV{BZ_QA_CONF_FILE};

    check_data_dir();
    wait_for_db();
    wait_for_httpd($conf->{browser_url});
    copy_qa_extension();

    chdir('/app/qa/t');
    run( 'prove', '-qf', '-Ilib', '-I/app', '-I/app/local/lib/perl5', glob('test_*.t') );
}


sub cmd_shell   { run( 'bash', '-l' ); }

sub cmd_version { run( 'cat', '/app/version.json' ); }

sub copy_qa_extension {
    say "copying the QA extension...";
    dircopy('/app/qa/extensions/QA', '/app/extensions/QA');
}

sub wait_for_db {
    die "/app/localconfig is missing\n" unless -f "/app/localconfig";

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

sub wait_for_httpd {
    my ($url) = @_;
    my $ok = 0;
    foreach (1..12) {
        say 'checking if httpd is up...' if $_ > 1;
        my $resp = get("$url/__lbheartbeat__");
        if ($resp && $resp =~ /^httpd OK$/) {
            $ok = 1;
            last;
        }
        say "httpd doesn't seem to be up at $url. waiting...";
        sleep(10);
    }
    die "unable to connect to httpd at $url\n" unless $ok;
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

    foreach my $var (Bugzilla::Install::Localconfig::LOCALCONFIG_VARS) {
        my $name = $var->{name};
        my $value = $localconfig->{$name};
        if (!defined $value) {
            $var->{default} = &{$var->{default}} if ref($var->{default}) eq 'CODE';
            $localconfig->{$name} = $var->{default};
        }
    }

    unlink($filename);

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
