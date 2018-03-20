# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Logger;

use 5.10.1;
use Moo;

use Bugzilla::Logging;
use Log::Log4perl;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::LogEntry;

# If Log4perl then finds that it's being called from a registered wrapper, it
# will automatically step up to the next call frame.
Log::Log4perl->wrapper_register(__PACKAGE__);

sub info {
    my ($this, $message) = @_;
    INFO($message);
}

sub error {
    my ($this, $message) = @_;
    ERROR($message);
}

sub debug {
    my ($this, $message) = @_;
    DEBUG($message);
}

sub result {
    my ($self, $connector, $message, $result, $data) = @_;
    $data ||= '';

    my $log_msg = sprintf
        '%s: Message #%s: %s %s',
        $connector->name,
        $message->message_id,
        push_result_to_string($result),
        $data;
    $self->info($log_msg);

    Bugzilla::Extension::Push::LogEntry->create({
        message_id   => $message->message_id,
        change_set   => $message->change_set,
        routing_key  => $message->routing_key,
        connector    => $connector->name,
        push_ts      => $message->push_ts,
        processed_ts => Bugzilla->dbh->selectrow_array('SELECT NOW()'),
        result       => $result,
        data         => $data,
    });
}

sub _build_logger { Log::Log4perl->get_logger(__PACKAGE__); }

1;
