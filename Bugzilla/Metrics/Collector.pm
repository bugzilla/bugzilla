# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Metrics::Collector;

use strict;
use warnings;

# the reporter needs to be a constant and use'd here to ensure it's loaded at
# compile time.
use constant REPORTER => 'Bugzilla::Metrics::Reporter::ElasticSearch';
use Bugzilla::Metrics::Reporter::ElasticSearch;

# Debugging reporter
#use constant REPORTER => 'Bugzilla::Metrics::Reporter::STDERR';
#use Bugzilla::Metrics::Reporter::STDERR;

use File::Basename;
use Time::HiRes qw(gettimeofday clock_gettime CLOCK_MONOTONIC);

sub new {
    my ($class, $name) = @_;
    my $self = {
        root => undef,
        head => undef,
        time => scalar(gettimeofday()),
    };
    bless($self, $class);
    $self->_start_timer({ type => 'main', name => $name });
    return $self;
}

sub end {
    my ($self, $timer) = @_;
    my $is_head = $timer ? 0 : 1;
    $timer ||= $self->{head};
    $timer->{duration} += clock_gettime(CLOCK_MONOTONIC) - $timer->{start_time};
    $self->{head} = $self->{head}->{parent} if $is_head;
}

sub DESTROY {
    my ($self) = @_;
    $self->finish() if $self->{head};
}

sub finish {
    my ($self) = @_;
    $self->end($self->{root});
    delete $self->{head};

    my $user = Bugzilla->user;
    if ($ENV{MOD_PERL}) {
        require Apache2::RequestUtil;
        my $request = eval { Apache2::RequestUtil->request };
        my $headers = $request ? $request->headers_in() : {};
        $self->{env} = {
            referer         => $headers->{Referer},
            request_method  => $request->method,
            request_uri     => basename($request->unparsed_uri),
            script_name     => $request->uri,
            user_agent      => $headers->{'User-Agent'},
        };
    }
    else {
        $self->{env} = {
            referer         => $ENV{HTTP_REFERER},
            request_method  => $ENV{REQUEST_METHOD},
            request_uri     => $ENV{REQUEST_URI},
            script_name     => basename($ENV{SCRIPT_NAME}),
            user_agent      => $ENV{HTTP_USER_AGENT},
        };
    }
    $self->{env}->{name}    = $self->{root}->{name};
    $self->{env}->{time}    = $self->{time};
    $self->{env}->{user_id} = $user->id;
    $self->{env}->{login}   = $user->login if $user->id;

    # remove passwords from request_uri
    $self->{env}->{request_uri} =~ s/\b((?:bugzilla_)?password=)(?:[^&]+|.+$)/$1x/gi;

    $self->report();
}

sub name {
    my ($self, $value) = @_;
    $self->{root}->{name} = $value if defined $value;
    return $self->{root}->{name};
}

sub db_start {
    my ($self) = @_;
    my $timer = $self->_start_timer({ type => 'db' });

    my @stack;
    my $i = 0;
    while (1) {
        my @caller = caller($i);
        last unless @caller;
        last if substr($caller[1], -5, 5) eq '.tmpl';
        push @stack, "$caller[1]:$caller[2]"
            unless substr($caller[1], 0, 16) eq 'Bugzilla/Metrics';
        $i++;
    }
    $timer->{stack} = \@stack;

    return $timer;
}

sub template_start {
    my ($self, $file) = @_;
    $self->_start_timer({ type => 'tmpl', file => $file });
}

sub memcached_start {
    my ($self, $key) = @_;
    $self->_start_timer({ type => 'memcached', key => $key });
}

sub memcached_end {
    my ($self, $hit) = @_;
    $self->{head}->{result} = $hit ? 'hit' : 'miss';
    $self->end();
}

sub resume {
    my ($self, $timer) = @_;
    $timer->{start_time} = clock_gettime(CLOCK_MONOTONIC);
    return $timer;
}

sub _start_timer {
    my ($self, $timer) = @_;
    $timer->{start_time} = $timer->{first_time} = clock_gettime(CLOCK_MONOTONIC);
    $timer->{duration} = 0;
    $timer->{children}   = [];

    if ($self->{head}) {
        $timer->{parent} = $self->{head};
        push @{ $self->{head}->{children} }, $timer;
    }
    else {
        $timer->{parent} = undef;
        $self->{root} = $timer;
    }
    $self->{head} = $timer;

    return $timer;
}

sub report {
    my ($self) = @_;
    my $class = REPORTER;
    $class->DETACH ? $class->background($self) : $class->foreground($self);
}

1;
