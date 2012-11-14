# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Push;

use strict;
use warnings;

use Bugzilla::Extension::Push::BacklogMessage;
use Bugzilla::Extension::Push::Config;
use Bugzilla::Extension::Push::Connectors;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Log;
use Bugzilla::Extension::Push::Logger;
use Bugzilla::Extension::Push::Message;
use Bugzilla::Extension::Push::Option;
use Bugzilla::Extension::Push::Queue;
use Bugzilla::Extension::Push::Util;
use DateTime;

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);
    $self->{is_daemon} = 0;
    return $self;
}

sub is_daemon {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{is_daemon} = $value ? 1 : 0;
    }
    return $self->{is_daemon};
}

sub start {
    my ($self) = @_;
    my $connectors = $self->connectors;
    $self->{config_last_modified} = $self->get_config_last_modified();
    $self->{config_last_checked} = (time);

    foreach my $connector ($connectors->list) {
        $connector->backlog->reset_backoff();
    }

    while(1) {
        $self->_reload();
        $self->push();
        sleep(POLL_INTERVAL_SECONDS);
    }
}

sub push {
    my ($self) = @_;
    my $logger = $self->logger;
    my $connectors = $self->connectors;

    my $enabled = 0;
    foreach my $connector ($connectors->list) {
        if ($connector->enabled) {
            $enabled = 1;
            last;
        }
    }
    return unless $enabled;

    $logger->debug("polling");

    # process each message
    while(my $message = $self->queue->oldest) {
        foreach my $connector ($connectors->list) {
            next unless $connector->enabled;
            next unless $connector->should_send($message);
            $logger->debug("pushing to " . $connector->name);

            my $is_backlogged = $connector->backlog->count;

            if (!$is_backlogged) {
                # connector isn't backlogged, immediate send
                $logger->debug("immediate send");
                my ($result, $data);
                eval {
                    ($result, $data) = $connector->send($message);
                };
                if ($@) {
                    $result = PUSH_RESULT_TRANSIENT;
                    $data   = clean_error($@);
                }
                if (!$result) {
                    $logger->error($connector->name . " failed to return a result code");
                    $result = PUSH_RESULT_UNKNOWN;
                }
                $logger->result($connector, $message, $result, $data);

                if ($result == PUSH_RESULT_TRANSIENT) {
                    $is_backlogged = 1;
                }
            }

            # if the connector is backlogged, push to the backlog queue
            if ($is_backlogged) {
                $logger->debug("backlogged");
                my $backlog = Bugzilla::Extension::Push::BacklogMessage->create_from_message($message, $connector);
            }
        }

        # message processed
        $message->remove_from_db();
    }

    # process backlog
    foreach my $connector ($connectors->list) {
        next unless $connector->enabled;
        my $message = $connector->backlog->oldest();
        next unless $message;

        $logger->debug("processing backlog for " . $connector->name);
        while ($message) {
            my ($result, $data);
            eval {
                ($result, $data) = $connector->send($message);
            };
            if ($@) {
                $result = PUSH_RESULT_TRANSIENT;
                $data   = $@;
            }
            $message->inc_attempts($result == PUSH_RESULT_OK ? '' : $data);
            if (!$result) {
                $logger->error($connector->name . " failed to return a result code");
                $result = PUSH_RESULT_UNKNOWN;
            }
            $logger->result($connector, $message, $result, $data);

            if ($result == PUSH_RESULT_TRANSIENT) {
                # connector is still down, stop trying
                $connector->backlog->inc_backoff();
                last;
            }

            # message was processed
            $message->remove_from_db();

            $message = $connector->backlog->oldest();
        }
    }
}

sub _reload {
    my ($self) = @_;

    # check for updated config every 60 seconds
    my $now = (time);
    if ($now - $self->{config_last_checked} < 60) {
        return;
    }
    $self->{config_last_checked} = $now;

    $self->logger->debug('Checking for updated configuration');
    if ($self->get_config_last_modified eq $self->{config_last_modified}) {
        return;
    }
    $self->{config_last_modified} = $self->get_config_last_modified();

    $self->logger->debug('Configuration has been updated');
    $self->connectors->reload();
}

sub get_config_last_modified {
    my ($self) = @_;
    my $options_list = Bugzilla::Extension::Push::Option->match({
        connector   => '*',
        option_name => 'last-modified',
    });
    if (@$options_list) {
        return $options_list->[0]->value;
    } else {
        return $self->set_config_last_modified();
    }
}

sub set_config_last_modified {
    my ($self) = @_;
    my $options_list = Bugzilla::Extension::Push::Option->match({
        connector   => '*',
        option_name => 'last-modified',
    });
    my $now = DateTime->now->datetime();
    if (@$options_list) {
        $options_list->[0]->set_value($now);
        $options_list->[0]->update();
    } else {
        Bugzilla::Extension::Push::Option->create({
            connector    => '*',
            option_name  => 'last-modified',
            option_value => $now,
        });
    }
    return $now;
}

sub config {
    my ($self) = @_;
    if (!$self->{config}) {
        $self->{config} = Bugzilla::Extension::Push::Config->new(
            'global',
            {
                name     => 'log_purge',
                label    => 'Purge logs older than (days)',
                type     => 'string',
                default  => '7',
                required => '1',
                validate => sub { $_[0] =~ /\D/ && die "Invalid purge duration (must be numeric)\n"; },
            },
        );
        $self->{config}->load();
    }
    return $self->{config};
}

sub logger {
    my ($self, $value) = @_;
    $self->{logger} = $value if $value;
    return $self->{logger};
}

sub connectors {
    my ($self, $value) = @_;
    $self->{connectors} = $value if $value;
    return $self->{connectors};
}

sub queue {
    my ($self) = @_;
    $self->{queue} ||= Bugzilla::Extension::Push::Queue->new();
    return $self->{queue};
}

sub log {
    my ($self) = @_;
    $self->{log} ||= Bugzilla::Extension::Push::Log->new();
    return $self->{log};
}

1;
