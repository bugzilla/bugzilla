# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Admin;

use strict;
use warnings;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Util qw(trim detaint_natural trick_taint);

use base qw(Exporter);
our @EXPORT = qw(
    admin_config
    admin_queues
    admin_log
);

sub admin_config {
    my ($vars) = @_;
    my $push = Bugzilla->push_ext;
    my $input = Bugzilla->input_params;

    if ($input->{save}) {
        my $dbh = Bugzilla->dbh;
        $dbh->bz_start_transaction();
        _update_config_from_form('global', $push->config);
        foreach my $connector ($push->connectors->list) {
            _update_config_from_form($connector->name, $connector->config);
        }
        $push->set_config_last_modified();
        $dbh->bz_commit_transaction();
        $vars->{message} = 'push_config_updated';
    }

    $vars->{push} = $push;
    $vars->{connectors} = $push->connectors;
}

sub _update_config_from_form {
    my ($name, $config) = @_;
    my $input = Bugzilla->input_params;

    # read values from form
    my $values = {};
    foreach my $option ($config->options) {
        my $option_name = $option->{name};
        $values->{$option_name} = trim($input->{$name . ".$option_name"});
    }

    # validate
    if ($values->{enabled} eq 'Enabled') {
        eval {
            $config->validate($values);
        };
        if ($@) {
            ThrowUserError('push_error', { error_message => clean_error($@) });
        }
    }

    # update
    foreach my $option ($config->options) {
        my $option_name = $option->{name};
        trick_taint($values->{$option_name});
        $config->{$option_name} = $values->{$option_name};
    }
    $config->update();
}

sub admin_queues {
    my ($vars, $page) = @_;
    my $push = Bugzilla->push_ext;
    my $input = Bugzilla->input_params;

    if ($page eq 'push_queues.html') {
        $vars->{push} = $push;

    } elsif ($page eq 'push_queues_view.html') {
        my $queue;
        if ($input->{connector}) {
            my $connector = $push->connectors->by_name($input->{connector})
                || ThrowUserError('push_error', { error_message => 'Invalid connector' });
            $queue = $connector->backlog;
        } else {
            $queue = $push->queue;
        }
        $vars->{queue} = $queue;

        my $id = $input->{message} || 0;
        detaint_natural($id)
            || ThrowUserError('push_error', { error_message => 'Invalid message ID' });
        my $message = $queue->by_id($id)
            || ThrowUserError('push_error', { error_message => 'Invalid message ID' });

        if ($input->{delete}) {
            $message->remove_from_db();
            $vars->{message} = 'push_message_deleted';

        } else {
            $vars->{message_obj} = $message;
            eval {
                $vars->{json} = to_json($message->payload_decoded, 1);
            };
        }
    }
}

sub admin_log {
    my ($vars) = @_;
    my $push = Bugzilla->push_ext;
    my $input = Bugzilla->input_params;

    $vars->{push} = $push;
}

1;
