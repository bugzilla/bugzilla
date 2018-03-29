# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# XXX In order to support Windows, we have to make gd_redirect_output
# use Log4Perl or something instead of calling "logger". We probably
# also need to use Win32::Daemon or something like that to daemonize.

package Bugzilla::JobQueue::Runner;

use 5.10.1;
use strict;
use warnings;
use autodie qw(open close unlink system);

use Bugzilla::Logging;
use Bugzilla::Constants;
use Bugzilla::DaemonControl qw(:utils);
use Bugzilla::JobQueue::Worker;
use Bugzilla::JobQueue;
use Bugzilla::Util qw(get_text);
use Cwd qw(abs_path);
use English qw(-no_match_vars $PROGRAM_NAME $EXECUTABLE_NAME);
use File::Basename;
use File::Copy;
use File::Spec::Functions qw(catfile tmpdir);
use Future;
use Future::Utils qw(fmap_void);
use IO::Async::Loop;
use IO::Async::Process;
use IO::Async::Signal;
use Pod::Usage;

use parent qw(Daemon::Generic);

our $VERSION = 2;

# Info we need to install/uninstall the daemon.
our $chkconfig  = '/sbin/chkconfig';
our $initd      = '/etc/init.d';
our $initscript = 'bugzilla-queue';

# The Daemon::Generic docs say that it uses all sorts of
# things from gd_preconfig, but in fact it does not. The
# only thing it uses from gd_preconfig is the "pidfile"
# config parameter.
sub gd_preconfig {
    my $self = shift;

    my $pidfile = $self->{gd_args}{pidfile};
    if ( !$pidfile ) {
        $pidfile = catfile(tmpdir(),  $self->{gd_progname} . '.pid');
    }
    return ( pidfile => $pidfile );
}

# All config other than the pidfile has to be done in gd_getopt
# in order for it to be set up early enough.
sub gd_getopt {
    my $self = shift;

    $self->SUPER::gd_getopt();

    if ( $self->{gd_args}{progname} ) {
        $self->{gd_progname} = $self->{gd_args}{progname};
    }
    else {
        $self->{gd_progname} = basename($PROGRAM_NAME);
    }

    # There are places that Daemon Generic's new() uses $PROGRAM_NAME instead of
    # gd_progname, which it really shouldn't, but this hack fixes it.
    $self->{_original_program_name} = $PROGRAM_NAME;

    ## no critic (Variables::RequireLocalizedPunctuationVars)
    $PROGRAM_NAME = $self->{gd_progname};
    ## use critic
}

sub gd_postconfig {
    my $self = shift;

    # See the hack above in gd_getopt. This just reverses it
    # in case anything else needs the accurate $0.
    ## no critic (Variables::RequireLocalizedPunctuationVars)
    $PROGRAM_NAME = delete $self->{_original_program_name};
    ## use critic
}

sub gd_more_opt {
    my $self = shift;
    return (
        'pidfile=s' => \$self->{gd_args}{pidfile},
        'n=s'       => \$self->{gd_args}{progname},
        'jobs|j=i'  => \$self->{gd_args}{jobs},
    );
}

sub gd_usage {
    pod2usage( { -verbose => 0, -exitval => 'NOEXIT' } );
    return 0;
}

sub gd_can_install {
    my $self = shift;

    my $source_file = "scripts/$initscript.rhel";
    my $dest_file   = "$initd/$initscript";
    my $sysconfig   = '/etc/sysconfig';
    my $config_file = "$sysconfig/$initscript";

    if ( !-x $chkconfig || !-d $initd ) {
        return $self->SUPER::gd_can_install(@_);
    }

    return sub {
        if ( !-w $initd ) {
            print "You must run the 'install' command as root.\n";
            return;
        }
        if ( -e $dest_file ) {
            print "$initscript already in $initd.\n";
        }
        else {
            copy( $source_file, $dest_file )
                or die "Could not copy $source_file to $dest_file: $!";
            chmod 0755, $dest_file
                or die "Could not change permissions on $dest_file: $!";
        }

        system $chkconfig, '--add', $initscript;
        print "$initscript installed.", " To start the daemon, do \"$dest_file start\" as root.\n";

        if ( -d $sysconfig and -w $sysconfig ) {
            if ( -e $config_file ) {
                print "$config_file already exists.\n";
                return;
            }

            open my $config_fh, '>', $config_file;
            my $directory = abs_path( dirname( $self->{_original_program_name} ) );
            my $owner_id  = ( stat $self->{_original_program_name} )[4];
            my $owner     = getpwuid $owner_id;
            print $config_fh <<"END";
#!/bin/sh
BUGZILLA="$directory"
USER=$owner
END
            close $config_fh;
        }
        else {
            print "Please edit $dest_file to configure the daemon.\n";
        }
        }
}

sub gd_can_uninstall {
    my $self = shift;

    if ( -x $chkconfig and -d $initd ) {
        return sub {
            if ( !-e "$initd/$initscript" ) {
                print "$initscript not installed.\n";
                return;
            }
            system $chkconfig, '--del', $initscript;
            print "$initscript disabled.", " To stop it, run: $initd/$initscript stop\n";
            }
    }

    return $self->SUPER::gd_can_install(@_);
}

sub gd_check {
    my $self = shift;

    # Get a count of all the jobs currently in the queue.
    my $jq    = Bugzilla->job_queue();
    my @dbs   = $jq->bz_databases();
    my $count = 0;
    foreach my $driver (@dbs) {
        $count += $driver->select_one( 'SELECT COUNT(*) FROM ts_job', [] );
    }
    print get_text( 'job_queue_depth', { count => $count } ) . "\n";
}

# override this to use IO::Async.
sub gd_setup_signals {
    my $self    = shift;
    my @signals = qw( INT HUP TERM );
    $self->{_signal_future} = Future->wait_any( map { catch_signal( $_, $_ ) } @signals );
}

sub gd_other_cmd {
    my ($self) = shift;
    if ( $ARGV[0] eq 'once' ) {
        Bugzilla::JobQueue::Worker->run('work_once');
        exit;
    }

    $self->SUPER::gd_other_cmd();
}

sub gd_quit_event     { FATAL('gd_quit_event() should never be called') }
sub gd_reconfig_event { FATAL('gd_reconfig_event() should never be called') }

sub gd_run {
    my $self      = shift;
    my $jobs      = $self->{gd_args}{jobs} // 1;
    my $signal_f  = $self->{_signal_future};
    my $workers_f = fmap_void { $self->run_worker() }
        concurrent => $jobs,
        generate   => sub { !$signal_f->is_ready };

    # This is so the process shows up in (h)top in a useful way.
    local $PROGRAM_NAME = "$self->{gd_progname} [supervisor]";
    Future->wait_any($signal_f, $workers_f)->get;
    unlink $self->{gd_pidfile};
    exit 0;
}

# This executes the script "jobqueue-worker.pl"
# $EXECUTABLE_NAME is the name of the perl interpreter.
sub run_worker {
    my ( $self ) = @_;

    my $script = catfile( bz_locations->{cgi_path}, 'jobqueue-worker.pl' );
    my @command = ( $EXECUTABLE_NAME, $script);
    if ( $self->{gd_args}{progname} ) {
        push @command, '--name' => "$self->{gd_args}{progname} [worker]";
    }

    my $loop   = IO::Async::Loop->new;
    my $exit_f = $loop->new_future;
    my $worker = IO::Async::Process->new(
        command      => \@command,
        on_finish    => on_finish($exit_f),
        on_exception => on_exception( 'jobqueue worker', $exit_f )
    );
    $exit_f->on_cancel(
        sub {
            DEBUG('terminate worker');
            $worker->kill('TERM');
        }
    );
    $loop->add($worker);
    return $exit_f;
}

1;

__END__

=head1 NAME

Bugzilla::JobQueue::Runner - A class representing the daemon that runs the
job queue.

=head1 SYNOPSIS

 use Bugzilla::JobQueue::Runner;
 Bugzilla::JobQueue::Runner->new();

=head1 DESCRIPTION

This is a subclass of L<Daemon::Generic> that is used by L<jobqueue>
to run the Bugzilla job queue.
