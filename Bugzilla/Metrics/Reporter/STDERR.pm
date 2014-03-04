# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Metrics::Reporter::STDERR;

use strict;
use warnings;

use parent 'Bugzilla::Metrics::Reporter';

use Data::Dumper;

use constant DETACH => 0;

sub report {
    my ($self) = @_;

    # count totals
    $self->{total} = $self->{times}->{duration};
    $self->{tmpl_count} = $self->{db_count} = $self->{mem_count} = 0;
    $self->{total_tmpl} = $self->{total_db} = $self->{mem_hits}  = 0;
    $self->{mem_keys} = {};
    $self->_tally($self->{times});

    # calculate percentages
    $self->{other} = $self->{total} - $self->{total_tmpl} - $self->{total_db};
    if ($self->{total} * 1) {
        $self->{perc_tmpl}  = $self->{total_tmpl} / $self->{total} * 100;
        $self->{perc_db}    = $self->{total_db} / $self->{total} * 100;
        $self->{perc_other} = $self->{other} / $self->{total} * 100;
    } else {
        $self->{perc_tmpl} = 0;
        $self->{perc_db} = 0;
        $self->{perc_other} = 0;
    }
    if ($self->{mem_count}) {
        $self->{perc_mem} = $self->{mem_hits} / $self->{mem_count} * 100;
    } else {
        $self->{perm_mem} = 0;
    }

    # convert to ms and format
    foreach my $key (qw( total total_tmpl total_db other )) {
        $self->{$key} = sprintf("%.4f", $self->{$key} * 1000);
    }
    foreach my $key (qw( perc_tmpl perc_db perc_other perc_mem )) {
        $self->{$key} = sprintf("%.1f", $self->{$key});
    }

    # massage each timer
    my $start_time = $self->{times}->{start_time};
    $self->walk_timers(sub {
        my ($timer) = @_;
        delete $timer->{parent};

        # show relative times
        $timer->{start_time} = $timer->{start_time} - $start_time;
        delete $timer->{end_time};

        # show times in ms instead of fractional seconds
        foreach my $field (qw( start_time duration duration_this )) {
            $timer->{$field} = sprintf('%.4f', $timer->{$field} * 1000) * 1
                if exists $timer->{$field};
        }
    });

    if (0) {
        # dump timers to stderr
        local $Data::Dumper::Indent = 1;
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Sortkeys = sub {
            my ($rh) = @_;
            return [ sort { $b cmp $a } keys %$rh ];
        };
        print STDERR Dumper($self->{env});
        print STDERR Dumper($self->{times});
    }

    # summary summary table too
    print STDERR <<EOF;
total time: $self->{total}
 tmpl time: $self->{total_tmpl} ($self->{perc_tmpl}%) $self->{tmpl_count} hits
   db time: $self->{total_db} ($self->{perc_db}%) $self->{db_count} hits
other time: $self->{other} ($self->{perc_other}%)
 memcached: $self->{perc_mem}% ($self->{mem_count} requests)
EOF
    my $tmpls = $self->{tmpl};
    my $len = 0;
    foreach my $file (keys %$tmpls) {
        $len = length($file) if length($file) > $len;
    }
    foreach my $file (sort { $tmpls->{$b}->{count} <=> $tmpls->{$a}->{count} } keys %$tmpls) {
        my $tmpl = $tmpls->{$file};
        printf STDERR
            "%${len}s: %2s hits %8.4f total %8.4f avg\n",
            $file,
            $tmpl->{count},
            $tmpl->{duration} * 1000,
            $tmpl->{duration} * 1000 / $tmpl->{count}
        ;
    }
    my $keys = $self->{mem_keys};
    $len = 0;
    foreach my $key (keys %$keys) {
        $len = length($key) if length($key) > $len;
    }
    foreach my $key (sort { $keys->{$a} <=> $keys->{$b} or $a cmp $b } keys %$keys) {
        printf STDERR "%${len}s: %s\n", $key, $keys->{$key};
    }
}

sub _tally {
    my ($self, $timer) = @_;
    if (exists $timer->{children}) {
        foreach my $child (@{ $timer->{children} }) {
            $self->_tally($child);
        }
    }

    if ($timer->{type} eq 'db') {
        $timer->{duration_this} = $timer->{duration};
        $self->{total_db} += $timer->{duration};
        $self->{db_count}++;

    } elsif ($timer->{type} eq 'tmpl') {
        my $child_duration = 0;
        if (exists $timer->{children}) {
            foreach my $child (@{ $timer->{children} }) {
                $child_duration += $child->{duration};
            }
        }
        $timer->{duration_this} = $timer->{duration} - $child_duration;

        $self->{total_tmpl} += $timer->{duration} - $child_duration;
        $self->{tmpl_count}++;
        $self->{tmpl}->{$timer->{file}}->{count}++;
        $self->{tmpl}->{$timer->{file}}->{duration} += $timer->{duration};

    } elsif ($timer->{type} eq 'memcached') {
        $timer->{duration_this} = $timer->{duration};
        $self->{mem_count}++;
        $self->{mem_keys}->{$timer->{key}}++;
        $self->{mem_hits}++ if $timer->{result} eq 'hit';
    }
}

1;
