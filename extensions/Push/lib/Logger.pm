# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Logger;

use strict;
use warnings;

use Apache2::Log;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::LogEntry;

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);
    return $self;
}

sub info  { shift->_log_it('INFO', @_) }
sub error { shift->_log_it('ERROR', @_) }
sub debug { shift->_log_it('DEBUG', @_) }

sub debugging {
    my ($self) = @_;
    return $self->{debug};
}

sub _log_it {
    my ($self, $method, $message) = @_;
    return if $method eq 'DEBUG' && !$self->debugging;
    chomp $message;
    if ($ENV{MOD_PERL}) {
        Apache2::ServerRec::warn("Push $method: $message");
    } elsif ($ENV{SCRIPT_FILENAME}) {
        print STDERR "Push $method: $message\n";
    } else {
        print STDERR '[' . localtime(time) ."] $method: $message\n";
    }
}

sub result {
    my ($self, $connector, $message, $result, $data) = @_;
    $data ||= '';

    $self->info(sprintf(
        "%s: Message #%s: %s %s",
        $connector->name,
        $message->message_id,
        push_result_to_string($result),
        $data
    ));

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

1;
