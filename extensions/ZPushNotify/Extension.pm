# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ZPushNotify;
use strict;
use warnings;

use base qw(Bugzilla::Extension);
our $VERSION = '1';

use Bugzilla;

#
# insert into the notifications table
#

sub _notify {
    my ($bug_id, $delta_ts) = @_;
    Bugzilla->dbh->do(
        "REPLACE INTO push_notify(bug_id, delta_ts) VALUES(?, ?)",
        undef,
        $bug_id, $delta_ts
    );
}

#
# object hooks
#

sub object_end_of_update {
    my ($self, $args) = @_;
    return unless Bugzilla->params->{enable_simple_push};
    return unless scalar keys %{ $args->{changes} };
    return unless my $object = $args->{object};
    if ($object->isa('Bugzilla::Attachment')) {
        _notify($object->bug->id, $object->bug->delta_ts);
    }
}

sub object_before_delete {
    my ($self, $args) = @_;
    return unless Bugzilla->params->{enable_simple_push};
    return unless my $object = $args->{object};
    if ($object->isa('Bugzilla::Attachment')) {
        _notify($object->bug->id, $object->bug->delta_ts);
    }
}

sub bug_end_of_update_delta_ts {
    my ($self, $args) = @_;
    return unless Bugzilla->params->{enable_simple_push};
    _notify($args->{bug_id}, $args->{timestamp});
}

sub bug_end_of_create {
    my ($self, $args) = @_;
    return unless Bugzilla->params->{enable_simple_push};
    _notify($args->{bug}->id, $args->{timestamp});
}

#
# schema / param
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'push_notify'} = {
        FIELDS => [
            id => {
                TYPE       => 'INTSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            bug_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'bugs',
                    COLUMN => 'bug_id',
                    DELETE => 'CASCADE'
                },
            },
            delta_ts => {
                TYPE       => 'DATETIME',
                NOTNULL    => 1,
            },
        ],
        INDEXES => [
            push_notify_idx => {
                FIELDS => [ 'bug_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
}

sub config_modify_panels {
    my ($self, $args) = @_;
    push @{ $args->{panels}->{advanced}->{params} }, {
        name    => 'enable_simple_push',
        type    => 'b',
        default => 0,
    };
}

__PACKAGE__->NAME;
