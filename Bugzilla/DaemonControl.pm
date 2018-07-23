# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::DaemonControl;
use 5.10.1;
use strict;
use warnings;

use Bugzilla::Logging;
use Bugzilla::Constants qw(bz_locations);
use Cwd qw(realpath);
use English qw(-no_match_vars $PROGRAM_NAME);
use File::Spec::Functions qw(catfile catdir);
use Future::Utils qw(repeat try_repeat);
use Future;
use IO::Async::Loop;
use IO::Async::Process;
use IO::Async::Protocol::LineStream;
use IO::Async::Signal;
use IO::Socket;
use LWP::Simple qw(get);
use POSIX qw(setsid WEXITSTATUS);

use base qw(Exporter);

our @EXPORT_OK = qw(
    run_httpd run_cereal run_jobqueue
    run_cereal_and_httpd run_cereal_and_jobqueue
    catch_signal on_finish on_exception
    assert_httpd assert_database assert_selenium
);

our %EXPORT_TAGS = (
    all   => \@EXPORT_OK,
    run   => [grep { /^run_/ } @EXPORT_OK],
    utils => [qw(catch_signal on_exception on_finish)],
);

my $BUGZILLA_DIR  = bz_locations->{cgi_path};
my $JOBQUEUE_BIN  = catfile( $BUGZILLA_DIR, 'jobqueue.pl' );
my $CEREAL_BIN    = catfile( $BUGZILLA_DIR, 'scripts', 'cereal.pl' );
my $HTTPD_BIN     = '/usr/sbin/httpd';
my $HTTPD_CONFIG  = catfile( bz_locations->{confdir}, 'httpd.conf' );

sub catch_signal {
    my ($name, @done)   = @_;
    my $loop     = IO::Async::Loop->new;
    my $signal_f = $loop->new_future;
    my $signal   = IO::Async::Signal->new(
        name       => $name,
        on_receipt => sub {
            my ($self) = @_;
            my $l = IO::Async::Loop->new;
            $signal_f->done(@done);
            $l->remove($self);
        }
    );
    $signal_f->on_cancel(
        sub {
            my $l = IO::Async::Loop->new;
            $l->remove($signal);
        },
    );

    $loop->add($signal);

    return $signal_f;
}

sub run_cereal {
    my $loop   = IO::Async::Loop->new;
    my $exit_f = $loop->new_future;
    my $cereal = IO::Async::Process->new(
        command      => [$CEREAL_BIN],
        on_finish    => on_finish($exit_f),
        on_exception => on_exception( 'cereal', $exit_f ),
    );
    $exit_f->on_cancel( sub { $cereal->kill('TERM') } );
    $exit_f->on_ready(
        sub {
            delete $ENV{LOG4PERL_STDERR_DISABLE};
        }
    );
    $loop->add($cereal);
    $ENV{LOG4PERL_STDERR_DISABLE} = 1;

    return $exit_f;
}

sub run_httpd {
    my (@args) = @_;

    my $loop   = IO::Async::Loop->new;
    my $exit_f = $loop->new_future;
    my $httpd  = IO::Async::Process->new(
        code => sub {

            # we have to setsid() to make a new process group
            # or else apache will kill its parent.
            setsid();
            my @command = ( $HTTPD_BIN, '-DFOREGROUND', '-f' => $HTTPD_CONFIG, @args );
            exec @command
              or die "failed to exec $command[0] $!";
        },
        on_finish    => on_finish($exit_f),
        on_exception => on_exception( 'httpd', $exit_f ),
    );
    $exit_f->on_cancel( sub { $httpd->kill('TERM') } );
    $loop->add($httpd);

    return $exit_f;
}

sub run_jobqueue {
    my (@args) = @_;

    my $loop     = IO::Async::Loop->new;
    my $exit_f   = $loop->new_future;
    my $jobqueue = IO::Async::Process->new(
        command   => [ $JOBQUEUE_BIN, 'start', '-f', '-d', @args ],
        on_finish => on_finish($exit_f),
        on_exception => on_exception( 'httpd', $exit_f ),
    );
    $exit_f->on_cancel( sub { $jobqueue->kill('TERM') } );
    $loop->add($jobqueue);

    return $exit_f;
}

sub run_cereal_and_jobqueue {
    my (@jobqueue_args) = @_;

    my $signal_f      = catch_signal('TERM', 0);
    my $cereal_exit_f = run_cereal();

    return assert_cereal()->then(
        sub {
            my $jobqueue_exit_f = run_jobqueue(@jobqueue_args);
            return Future->wait_any($cereal_exit_f, $jobqueue_exit_f, $signal_f);
        }
    );
}

sub run_cereal_and_httpd {
    my @httpd_args = @_;

    my $signal_f      = catch_signal('TERM', 0);
    my $cereal_exit_f = run_cereal();

    return assert_cereal()->then(
        sub {
            push @httpd_args, '-DNETCAT_LOGS';

            my $lc = Bugzilla::Install::Localconfig::read_localconfig();
            if ( ($lc->{inbound_proxies} // '') eq '*' && $lc->{urlbase} =~ /^https/) {
                push @httpd_args, '-DHTTPS';
            }
            elsif ($lc->{urlbase} =~ /^https/) {
                WARN('HTTPS urlbase but inbound_proxies is not "*"');
            }
            my $httpd_exit_f  = run_httpd(@httpd_args);

            return Future->wait_any($cereal_exit_f, $httpd_exit_f, $signal_f);
        }
    );
}

sub assert_httpd {
    my $loop = IO::Async::Loop->new;
    my $port  = $ENV{PORT} // 8000;
    my $repeat = repeat {
        $loop->delay_future(after => 0.25)->then(
            sub {
                Future->wrap(get("http://localhost:$port/__lbheartbeat__") // '');
            },
        );
    } until => sub {
        my $f = shift;
        ( $f->get =~ /^httpd OK/ );
    };
    my $timeout = $loop->timeout_future(after => 20)->else_fail('assert_httpd timeout');
    return Future->wait_any($repeat, $timeout);
}

sub assert_selenium {
    my ($host, $port) = @_;
    $host //= 'localhost';
    $port //= 4444;

    return assert_connect($host, $port, 'assert_selenium');
}

sub assert_cereal {
    return assert_connect(
        'localhost',
        $ENV{LOGGING_PORT} // 5880,
        'assert_cereal'
    );
}

sub assert_connect {
    my ($host, $port, $name) = @_;
    my $loop = IO::Async::Loop->new;
    my $repeat = repeat {
        $loop->delay_future(after => 1)->then(
            sub {
                my $sock = IO::Socket::INET->new( PeerAddr => $host, PeerPort => $port );
                Future->wrap($sock ? 1 : 0);
            },
        );
    } until => sub { shift->get };
    my $timeout = $loop->timeout_future(after => 60)->else_fail("$name timeout");
    return Future->wait_any($repeat, $timeout);
}

sub assert_database {
    my $loop = IO::Async::Loop->new;
    my $lc   = Bugzilla::Install::Localconfig::read_localconfig();

    for my $var (qw(db_name db_host db_user db_pass)) {
        return $loop->new_future->die("$var is not set!") unless $lc->{$var};
    }

    my $dsn    = "dbi:mysql:database=$lc->{db_name};host=$lc->{db_host}";
    my $repeat = repeat {
        $loop->delay_future( after => 0.25 )->then(
            sub {
                my $dbh = DBI->connect(
                    $dsn,
                    $lc->{db_user},
                    $lc->{db_pass},
                    { RaiseError => 0, PrintError => 0 },
                );
                Future->wrap($dbh);
            }
        );
    } until => sub { defined shift->get };

    my $timeout = $loop->timeout_future( after => 20 )->else_fail('assert_database timeout');
    my $any_f = Future->wait_any( $repeat, $timeout );
    return $any_f->transform(
        done => sub { return },
        fail => sub { "unable to connect to $dsn as $lc->{db_user}" },
    );
}

sub on_finish {
    my ($f) = @_;

    return sub {
        my ($self, $exitcode) = @_;
        $f->done(WEXITSTATUS($exitcode));
    };
}

sub on_exception {
    my ( $name, $f ) = @_;

    return sub {
        my ( $self, $exception, $errno, $exitcode ) = @_;

        if ( length $exception ) {
            $f->fail( "$name died with the exception $exception (errno was $errno)\n" );
        }
        elsif ( ( my $status = WEXITSTATUS($exitcode) ) == 255 ) {
            $f->fail("$name failed to exec() - $errno\n");
        }
        else {
            $f->fail("$name exited with exit status $status\n");
        }
    };
}

1;

__END__

=head1 NAME

Bugzilla::DaemonControl - Utility functions for controlling daemons

=head1 SYNOPSIS

    my $httpd_exit_code_f = run_httpd(@httpd_args);
    my $signal_f = catch_signal("TERM");

=head1 DESCRIPTION

This module exports functions that either start daemons (L<run_httpd()>, L<run_cereal()>),
check for running services (L<assert_httpd()>, L<assert_database()>, L<assert_selenium()>),
or help build more functions like the above (L<on_exception()>, L<on_finish()>).

The C<run_> and C<assert_> functions return Futures, see L<Future> for details
on that. But if you've used Promises in the javascript, Futures are the same concept.

=head1 FUNCTIONS

Nothing is exported by default, but you can request C<:all> for that.
You can also just get the run_* functions with C<:run>.

=head2 run_httpd()

This function starts an httpd and returns a future that is B<done> when the httpd exits.
The return value will be the exit code of the process.

Thus the following program would exit with whatever value httpd exits with:

    exit run_httpd()->get;

It may also B<fail> in unlikely situations, such as a L<fork()> failing, httpd not being found, etc.

Canceling the future will send C<SIGTERM> to httpd.

=head2 run_cereal()

This runs a builtin process that listens on C<localhost:5880> for TCP
connections. Each connection may send lines of text, and those lines of text
will be written to B<STDOUT>. Once you start this, you should limit or stop
entirely printing to B<STDOUT> to ensure that output is well-ordered.

If you need to listen on a different port, set the environmental variable
C<LOGGING_PORT>.

This returns a future similar to L<run_httpd()>.
Canceling the future will terminate the cereal daemon.

=head2 run_cereal_and_httpd()

This will start up cereal and the httpd. It will return a future
that is B<done> when either httpd or cereal exits.
The future will also be B<done> if C<SIGTERM> is sent to the process that calls
this function.

Because of how futures work, when one of these processes is done (or when we get the signal)
the other futures are canceled.

This means that if cereal exits, httpd will exit.
And if httpd exits, cereal will exit.

=head2 assert_database()

This provides a simple way to wait on the database being up.
It will either be B<done> with no usable return value, or fail with a timeout error.

    # wait until we have a database
    assert_database()->get;

=head2 assert_seleniuim()

This returns a future that is complete when we can reach selenium,
or it fails with a timeout.

=head2 assert_httpd()

This returns a future that is complete when we can reach the __lbheartbeat__
endpoint, or it fails with a timeout.

=head2 on_finish($f)

This returns a callback that will complete a future. It is to be used with L<IO::Async::Process>.

=head2 on_exception($f)

This returns a callback that will fail a future. It is to be used with L<IO::Async::Process>.
