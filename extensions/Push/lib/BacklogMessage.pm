# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::BacklogMessage;

use strict;
use warnings;

use base 'Bugzilla::Object';

use constant AUDIT_CREATES => 0;
use constant AUDIT_UPDATES => 0;
use constant AUDIT_REMOVES => 0;
use constant USE_MEMCACHED => 0;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Util;
use Encode;

#
# initialisation
#

use constant DB_TABLE => 'push_backlog';
use constant DB_COLUMNS => qw(
    id
    message_id
    push_ts
    payload
    change_set
    routing_key
    connector
    attempt_ts
    attempts
    last_error
);
use constant UPDATE_COLUMNS => qw(
    attempt_ts
    attempts
    last_error
);
use constant LIST_ORDER => 'push_ts';
use constant VALIDATORS => {
    payload     => \&_check_payload,
    change_set  => \&_check_change_set,
    routing_key => \&_check_routing_key,
    connector   => \&_check_connector,
    attempts    => \&_check_attempts,
};

#
# constructors
#

sub create_from_message {
    my ($class, $message, $connector) = @_;
    my $self = $class->create({
        message_id => $message->id,
        push_ts => $message->push_ts,
        payload => $message->payload,
        change_set => $message->change_set,
        routing_key => $message->routing_key,
        connector => $connector->name,
        attempt_ts => undef,
        attempts => 0,
        last_error => undef,
    });
    return $self;
}

#
# accessors
#

sub message_id  { return $_[0]->{'message_id'}   }
sub push_ts     { return $_[0]->{'push_ts'};     }
sub payload     { return $_[0]->{'payload'};     }
sub change_set  { return $_[0]->{'change_set'};  }
sub routing_key { return $_[0]->{'routing_key'}; }
sub connector   { return $_[0]->{'connector'};   }
sub attempt_ts  { return $_[0]->{'attempt_ts'};  }
sub attempts    { return $_[0]->{'attempts'};    }
sub last_error  { return $_[0]->{'last_error'};  }

sub payload_decoded {
    my ($self) = @_;
    return from_json($self->{'payload'});
}

sub attempt_time {
    my ($self) = @_;
    if (!exists $self->{'attempt_time'}) {
        $self->{'attempt_time'} = datetime_from($self->attempt_ts)->epoch;
    }
    return $self->{'attempt_time'};
}

#
# mutators
#

sub inc_attempts {
    my ($self, $error) = @_;
    $self->{attempt_ts} = Bugzilla->dbh->selectrow_array('SELECT NOW()');
    $self->{attempts} = $self->{attempts} + 1;
    $self->{last_error} = $error;
    $self->update;
}

#
# validators
#

sub _check_payload {
    my ($invocant, $value) = @_;
    length($value) || ThrowCodeError('push_invalid_payload');
    return $value;
}

sub _check_change_set {
    my ($invocant, $value) = @_;
    (defined($value) && length($value)) || ThrowCodeError('push_invalid_change_set');
    return $value;
}

sub _check_routing_key {
    my ($invocant, $value) = @_;
    (defined($value) && length($value)) || ThrowCodeError('push_invalid_routing_key');
    return $value;
}

sub _check_connector {
    my ($invocant, $value) = @_;
    Bugzilla->push_ext->connectors->exists($value) || ThrowCodeError('push_invalid_connector');
    return $value;
}

sub _check_attempts {
    my ($invocant, $value) = @_;
    return $value || 0;
}

1;

