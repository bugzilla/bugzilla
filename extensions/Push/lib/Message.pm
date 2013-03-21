# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Message;

use strict;
use warnings;

use base 'Bugzilla::Object';

use constant AUDIT_CREATES => 0;
use constant AUDIT_UPDATES => 0;
use constant AUDIT_REMOVES => 0;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Extension::Push::Util;
use Encode;

#
# initialisation
#

use constant DB_TABLE => 'push';
use constant DB_COLUMNS => qw(
    id
    push_ts
    payload
    change_set
    routing_key
);
use constant LIST_ORDER => 'push_ts';
use constant VALIDATORS => {
    push_ts     => \&_check_push_ts,
    payload     => \&_check_payload,
    change_set  => \&_check_change_set,
    routing_key => \&_check_routing_key,
};

# this creates an object which doesn't exist on the database
sub new_transient {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $object   = shift;
    bless($object, $class) if $object;
    return $object;
}

# take a transient object and commit
sub create_from_transient {
    my ($self) = @_;
    return $self->create($self);
}

#
# accessors
#

sub push_ts     { return $_[0]->{'push_ts'};     }
sub payload     { return $_[0]->{'payload'};     }
sub change_set  { return $_[0]->{'change_set'};  }
sub routing_key { return $_[0]->{'routing_key'}; }
sub message_id  { return $_[0]->id;              }

sub payload_decoded {
    my ($self) = @_;
    return from_json($self->{'payload'});
}

#
# validators
#

sub _check_push_ts {
    my ($invocant, $value) = @_;
    $value ||= Bugzilla->dbh->selectrow_array('SELECT NOW()');
    return $value;
}

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

1;

