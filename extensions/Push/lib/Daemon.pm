# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Daemon;

use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Push;
use Bugzilla::Extension::Push::Logger;
use Carp qw(confess);
use Daemon::Generic;
use File::Basename;
use Pod::Usage;

sub start {
    newdaemon();
}

#
# daemon::generic config
#

sub gd_preconfig {
    my $self = shift;
    my $pidfile = $self->{gd_args}{pidfile};
    if (!$pidfile) {
        $pidfile = bz_locations()->{datadir} . '/' . $self->{gd_progname} . ".pid";
    }
    return (pidfile => $pidfile);
}

sub gd_getopt {
    my $self = shift;
    $self->SUPER::gd_getopt();
    if ($self->{gd_args}{progname}) {
        $self->{gd_progname} = $self->{gd_args}{progname};
    } else {
        $self->{gd_progname} = basename($0);
    }
    $self->{_original_zero} = $0;
    $0 = $self->{gd_progname};
}

sub gd_postconfig {
    my $self = shift;
    $0 = delete $self->{_original_zero};
}

sub gd_more_opt {
    my $self = shift;
    return (
        'pidfile=s' => \$self->{gd_args}{pidfile},
        'n=s'       => \$self->{gd_args}{progname},
    );
}

sub gd_usage {
    pod2usage({ -verbose => 0, -exitval => 'NOEXIT' });
    return 0;
};

sub gd_redirect_output {
    my $self = shift;

    my $filename = bz_locations()->{datadir} . '/' . $self->{gd_progname} . ".log";
    open(STDERR, ">>$filename") or (print "could not open stderr: $!" && exit(1));
    close(STDOUT);
    open(STDOUT, ">&STDERR") or die "redirect STDOUT -> STDERR: $!";
    $SIG{HUP} = sub {
        close(STDERR);
        open(STDERR, ">>$filename") or (print "could not open stderr: $!" && exit(1));
    };
}

sub gd_setup_signals {
    my $self = shift;
    $self->SUPER::gd_setup_signals();
    $SIG{TERM} = sub { $self->gd_quit_event(); }
}

sub gd_run {
    my $self = shift;
    $::SIG{__DIE__} = \&Carp::confess if $self->{debug};
    my $push = Bugzilla->push_ext;
    $push->logger->{debug} = $self->{debug};
    $push->is_daemon(1);
    $push->start();
}

1;
