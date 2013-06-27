# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Instrument;

use strict;
use warnings;

use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use Encode qw(encode_utf8);
use Sys::Syslog qw(:DEFAULT);

sub new {
    my ($class, $label) = @_;
    my $self = bless({ times => [], labels => [], values => [] }, $class);
    $self->label($label);
    $self->time('start_time');
    return $self;
}

sub time {
    my ($self, $name) = @_;
    # for now $name isn't used
    push @{ $self->{times} }, clock_gettime(CLOCK_MONOTONIC);
}

sub label {
    my ($self, $value) = @_;
    push @{ $self->{labels} }, $value;
}

sub value {
    my ($self, $name, $value) = @_;
    # for now $name isn't used
    push @{ $self->{values} }, $value;
}

sub log {
    my $self = shift;

    my @times = @{ $self->{times} };
    return unless scalar(@times) >= 2;
    my @labels = @{ $self->{labels} };
    my @values = @{ $self->{values} };

    # calculate diffs
    my @diffs = ($times[$#times] - $times[0]);
    while (1) {
        my $start = shift(@times);
        last unless scalar(@times);
        push @diffs, $times[0] - $start;
    }

    # build syslog string
    my $format = '[timing]' . (' %s' x scalar(@labels)) . (' %.6f' x scalar(@diffs)) . (' %s' x scalar(@values));
    my $entry = sprintf($format, @labels, @diffs, @values);

    # and log
    openlog('apache', 'cons,pid', 'local4');
    syslog('notice', encode_utf8($entry));
    closelog();
}

1;
