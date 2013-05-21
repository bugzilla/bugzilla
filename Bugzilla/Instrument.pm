# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Instrument;

use strict;
use warnings;

use Bugzilla::Constants;
use FileHandle;
use Sys::Hostname;
use Time::HiRes qw(time);

sub new {
    my ($class, $name) = @_;
    my $self = {
        name    => $name,
        times   => [],
        fh      => FileHandle->new('>>' . _filename($name)),
    };
    return bless($self, $class);
}

sub DESTROY {
    my ($self) = @_;
    $self->{fh}->print("\n");
    $self->{fh}->close();
}

sub begin {
    my ($self, $label) = @_;
    my $now = (time);
    push @{ $self->{times} }, { time => $now, label => $label };
    $self->_log($now, undef, $label);
}

sub end {
    my ($self, $label) = @_;
    my $now = (time);
    my $timer = pop @{ $self->{times} };
    my $start = $timer ? $timer->{time} : undef;
    $label ||= $timer->{label} if $timer;
    $self->_log($now, $start, $label);
}

sub _log {
    my ($self, $now, $then, $label) = @_;
    $label ||= '';
    my $level = scalar(@{ $self->{times} });
    if ($then) {
        $label = ('<' x ($level + 1)) . ' ' . $label;
        $self->{fh}->printf("[%.5f] %-60s (+%.4f)\n", $now, $label, $now - $then);
    } else {
        $label = ('>' x $level) . ' ' . $label;
        $self->{fh}->printf("[%.5f] %s\n", $now, $label);
    }
}

our ($_path, $_host);
sub _filename {
    my ($name) = @_;
    if (!$_path) {
        $_path = bz_locations()->{datadir} . "/timings";
        mkdir($_path) unless -d $_path;
        $_host = hostname();
        $_host =~ s/^([^\.]+)\..+/$1/;
    }
    return "$_path/$name-$_host-$$.log";
}

1;
