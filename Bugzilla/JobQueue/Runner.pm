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

# XXX In order to support Windows, we have to make gd_redirect_output
# use Log4Perl or something instead of calling "logger". We probably
# also need to use Win32::Daemon or something like that to daemonize.

package Bugzilla::JobQueue::Runner;

use strict;
use File::Basename;
use Pod::Usage;

use Bugzilla::Constants;
use Bugzilla::JobQueue;
use Bugzilla::Util qw(get_text);
BEGIN { eval "use base qw(Daemon::Generic)"; }

# Required because of a bug in Daemon::Generic where it won't use the
# "version" key from DAEMON_CONFIG.
our $VERSION = BUGZILLA_VERSION;

use constant DAEMON_CONFIG => (
    progname => basename($0),
    pidfile  => bz_locations()->{datadir} . '/' . basename($0) . '.pid',
    version  => BUGZILLA_VERSION,
);

sub gd_preconfig {
    return DAEMON_CONFIG;
}

sub gd_usage {
    pod2usage({ -verbose => 0, -exitval => 'NOEXIT' });
    return 0
}

sub gd_check {
    my $self = shift;

    # Get a count of all the jobs currently in the queue.
    my $jq = Bugzilla->job_queue();
    my @dbs = $jq->bz_databases();
    my $count = 0;
    foreach my $driver (@dbs) {
        $count += $driver->select_one('SELECT COUNT(*) FROM ts_job', []);
    }
    print get_text('job_queue_depth', { count => $count }) . "\n";
}

sub gd_run {
    my $self = shift;

    my $jq = Bugzilla->job_queue();
    $jq->set_verbose($self->{debug});
    foreach my $module (values %{ Bugzilla::JobQueue::JOB_MAP() }) {
        eval "use $module";
        $jq->can_do($module);
    }
    $jq->work;
}

1;

__END__

=head1 NAME

Bugzilla::JobQueue::Runner - A class representing the daemon that runs the
job queue.

 use Bugzilla::JobQueue::Runner;
 Bugzilla::JobQueue::Runner->new();

=head1 DESCRIPTION

This is a subclass of L<Daemon::Generic> that is used by L<jobqueue>
to run the Bugzilla job queue.
