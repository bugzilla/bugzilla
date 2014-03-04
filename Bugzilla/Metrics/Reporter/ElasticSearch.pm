# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Metrics::Reporter::ElasticSearch;

use strict;
use warnings;

use parent 'Bugzilla::Metrics::Reporter';

use constant DETACH => 1;

sub report {
    my ($self) = @_;

    # build path array and flatten
    my @timers;
    $self->walk_timers(sub {
        my ($timer, $parent) = @_;
        $timer->{id} = scalar(@timers);
        if ($parent) {
            if (exists $timer->{children}) {
                if ($timer->{type} eq 'tmpl') {
                    $timer->{node} = 'tmpl: ' . $timer->{file};
                }
                elsif ($timer->{type} eq 'db') {
                    $timer->{node} = 'db';
                }
                else {
                    $timer->{node} = '?';
                }
            }
            $timer->{path} = [ @{ $parent->{path} }, $parent->{node} ];
            $timer->{parent} = $parent->{id};
        }
        else {
            $timer->{path} = [ ];
            $timer->{node} = $timer->{name};
        }
        push @timers, $timer;
    });

    # calculate timer-only durations
    $self->walk_timers(sub {
        my ($timer) = @_;
        my $child_duration = 0;
        if (exists $timer->{children}) {
            foreach my $child (@{ $timer->{children} }) {
                $child_duration += $child->{duration};
            }
        }
        $timer->{this_duration} = $timer->{duration} - $child_duration;
    });

    # massage each timer
    my $start_time = $self->{times}->{start_time};
    foreach my $timer (@timers) {
        # remove node name and children
        delete $timer->{node};
        delete $timer->{children};

        # show relative times
        $timer->{start_time} = $timer->{start_time} - $start_time;
        delete $timer->{end_time};

        # show times in ms instead of fractional seconds
        foreach my $field (qw( start_time duration this_duration )) {
            $timer->{$field} = sprintf('%.4f', $timer->{$field} * 1000) * 1;
        }
    }

    # remove private data from env
    delete $self->{env}->{user_agent};
    delete $self->{env}->{referer};

    # throw at ES
    require ElasticSearch;
    ElasticSearch->new(
        servers     => Bugzilla->params->{metrics_elasticsearch_server},
        transport   => 'http',
    )->index(
        index   => Bugzilla->params->{metrics_elasticsearch_index},
        type    => Bugzilla->params->{metrics_elasticsearch_type},
        ttl     => Bugzilla->params->{metrics_elasticsearch_ttl},
        data    => {
            env     => $self->{env},
            times   => \@timers,
        },
    );
}

1;
