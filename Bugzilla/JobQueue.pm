# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Mozilla Corporation.
# Portions created by the Initial Developer are Copyright (C) 2008
# Mozilla Corporation. All Rights Reserved.
#
# Contributor(s): 
#   Mark Smith <mark@mozilla.com>
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::JobQueue;

use strict;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Install::Util qw(install_string);
use File::Slurp;
use base qw(TheSchwartz);
use fields qw(_worker_pidfile);

# This maps job names for Bugzilla::JobQueue to the appropriate modules.
# If you add new types of jobs, you should add a mapping here.
use constant JOB_MAP => {
    send_mail => 'Bugzilla::Job::Mailer',
};

# Without a driver cache TheSchwartz opens a new database connection
# for each email it sends.  This cached connection doesn't persist
# across requests.
use constant DRIVER_CACHE_TIME => 300; # 5 minutes

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
            dsn    => Bugzilla->dbh_main->{private_bz_dsn},
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

# To avoid memory leaks/fragmentation which tends to happen for long running
# perl processes; check for jobs, and spawn a new process to empty the queue.
sub subprocess_worker {
    my $self = shift;

    my $command = "$0 -d -p '" . $self->{_worker_pidfile} . "' onepass";

    while (1) {
        my $time = (time);
        my @jobs = $self->list_jobs({
            funcname      => $self->{all_abilities},
            run_after     => $time,
            grabbed_until => $time,
            limit         => 1,
        });
        if (@jobs) {
            $self->debug("Spawning queue worker process");
            # Run the worker as a daemon
            system $command;
            # And poll the PID to detect when the working has finished.
            # We do this instead of system() to allow for the INT signal to
            # interrup us and trigger kill_worker().
            my $pid = read_file($self->{_worker_pidfile}, err_mode => 'quiet');
            if ($pid) {
                sleep(3) while(kill(0, $pid));
            }
            $self->debug("Queue worker process completed");
        } else {
            $self->debug("No jobs found");
        }
        sleep(5);
    }
}

sub kill_worker {
    my $self = Bugzilla->job_queue();
    if ($self->{_worker_pidfile} && -e $self->{_worker_pidfile}) {
        my $worker_pid = read_file($self->{_worker_pidfile});
        if ($worker_pid && kill(0, $worker_pid)) {
            $self->debug("Stopping worker process");
            system "$0 -f -p '" . $self->{_worker_pidfile} . "' stop";
        }
    }
}

sub set_pidfile {
    my ($self, $pidfile) = @_;
    $pidfile =~ s/^(.+)(\..+)$/$1.worker$2/;
    $self->{_worker_pidfile} = $pidfile;
}

# Clear the request cache at the start of each run.
sub work_once {
    my $self = shift;
    Bugzilla->clear_request_cache();
    return $self->SUPER::work_once(@_);
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
