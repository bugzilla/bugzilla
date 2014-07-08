# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugmailFilter;
use strict;
use warnings;

use base qw(Bugzilla::Extension);
our $VERSION = '1';

#
# schema / install
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{schema}->{bugmail_filters} = {
        FIELDS => [
            id => {
                TYPE       => 'INTSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE'
                },
            },
            field_name => {
                # due to fake fields, this can't be field_id
                TYPE       => 'VARCHAR(64)',
                NOTNULL    => 0,
            },
            product_id => {
                TYPE       => 'INT2',
                NOTNULL    => 0,
                REFERENCES => {
                    TABLE  => 'products',
                    COLUMN => 'id',
                    DELETE => 'CASCADE'
                },
            },
            component_id => {
                TYPE       => 'INT2',
                NOTNULL    => 0,
                REFERENCES => {
                    TABLE  => 'components',
                    COLUMN => 'id',
                    DELETE => 'CASCADE'
                },
            },
            relationship => {
                TYPE       => 'INT2',
                NOTNULL    => 0,
            },
            action => {
                TYPE       => 'INT1',
                NOTNULL    => 1,
            },
        ],
        INDEXES => [
            bugmail_filters_unique_idx => {
                FIELDS  => [ qw( user_id field_name product_id component_id
                                 relationship ) ],
                TYPE    => 'UNIQUE',
            },
            bugmail_filters_user_idx => [
                'user_id',
            ],
        ],
    };
}

__PACKAGE__->NAME;
