# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::JobQueue;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Logging;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Install::Util qw(install_string);
use Bugzilla::DaemonControl qw(catch_signal);
use IO::Async::Timer::Periodic;
use IO::Async::Loop;
use Future;
use base qw(TheSchwartz);

# This maps job names for Bugzilla::JobQueue to the appropriate modules.
# If you add new types of jobs, you should add a mapping here.
use constant JOB_MAP => {
    send_mail => 'Bugzilla::Job::Mailer',
    bug_mail  => 'Bugzilla::Job::BugMail',
};

# Without a driver cache TheSchwartz opens a new database connection
# for each email it sends.  This cached connection doesn't persist
# across requests.
use constant DRIVER_CACHE_TIME => 300; # 5 minutes

# To avoid memory leak/fragmentation, a worker process won't process more than
# MAX_MESSAGES messages.
use constant MAX_MESSAGES => 75;

sub job_map {
    if (!defined(Bugzilla->request_cache->{job_map})) {
        my $job_map = JOB_MAP;
        Bugzilla::Hook::process('job_map', { job_map => $job_map });
        Bugzilla->request_cache->{job_map} = $job_map;
    }

    return Bugzilla->request_cache->{job_map};
}

sub new {
    my $class = shift;

    if (!Bugzilla->feature('jobqueue')) {
        ThrowCodeError('feature_disabled', { feature => 'jobqueue' });
    }

    my $lc = Bugzilla->localconfig;
    # We need to use the main DB as TheSchwartz module is going
    # to write to it.
    my $self = $class->SUPER::new(
        databases => [{
            dsn    => Bugzilla->dbh_main->dsn,
            user   => $lc->{db_user},
            pass   => $lc->{db_pass},
            prefix => 'ts_',
        }],
        driver_cache_expiration => DRIVER_CACHE_TIME,
    );

    return $self;
}

# A way to get access to the underlying databases directly.
sub bz_databases {
    my $self = shift;
    my @hashes = keys %{ $self->{databases} };
    return map { $self->driver_for($_) } @hashes;
}

# inserts a job into the queue to be processed and returns immediately
sub insert {
    my $self = shift;
    my $job = shift;

    my $mapped_job = Bugzilla::JobQueue->job_map()->{$job};
    ThrowCodeError('jobqueue_no_job_mapping', { job => $job })
        if !$mapped_job;
    unshift(@_, $mapped_job);

    my $retval = $self->SUPER::insert(@_);
    # XXX Need to get an error message here if insert fails, but
    # I don't see any way to do that in TheSchwartz.
    ThrowCodeError('jobqueue_insert_failed', { job => $job, errmsg => $@ })
        if !$retval;

    return $retval;
}

sub debug {
    my ($self, @args) = @_;
    my $caller_pkg = caller;
    local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + 1;
    my $logger = Log::Log4perl->get_logger($caller_pkg);
    if ($args[0] && $args[0] eq "TheSchwartz::work_once found no jobs") {
        $logger->trace(@args);
    }
    else {
        $logger->info(@args);
    }
}

sub work {
    my ($self, $delay) = @_;
    $delay ||= 1;
    my $loop  = IO::Async::Loop->new;
    my $timer = IO::Async::Timer::Periodic->new(
        first_interval => 0,
        interval       => $delay,
        reschedule     => 'drift',
        on_tick        => sub { $self->work_once }
    );
    DEBUG("working every $delay seconds");
    $loop->add($timer);
    $timer->start;
    Future->wait_any(map { catch_signal($_) } qw( INT TERM HUP ))->get;
    $timer->stop;
    $loop->remove($timer);
}

# Clear the request cache at the start of each run.
sub work_once {
    my $self = shift;
    my $val = $self->SUPER::work_once(@_);
    Bugzilla::Hook::process('request_cleanup');
    Bugzilla::Bug->CLEANUP;
    Bugzilla->clear_request_cache();
    return $val;
}

# Never process more than MAX_MESSAGES in one batch, to avoid memory
# leak/fragmentation issues.
sub work_until_done {
    my $self = shift;
    my $count = 0;
    while ($count++ < MAX_MESSAGES) {
        $self->work_once or last;
    }
}

1;

__END__

=head1 NAME

Bugzilla::JobQueue - Interface between Bugzilla and TheSchwartz.

=head1 SYNOPSIS

 use Bugzilla;

 my $obj = Bugzilla->job_queue();
 $obj->insert('send_mail', { msg => $message });

=head1 DESCRIPTION

Certain tasks should be done asyncronously.  The job queue system allows
Bugzilla to use some sort of service to schedule jobs to happen asyncronously.

=head2 Inserting a Job

See the synopsis above for an easy to follow example on how to insert a
job into the queue.  Give it a name and some arguments and the job will
be sent away to be done later.
