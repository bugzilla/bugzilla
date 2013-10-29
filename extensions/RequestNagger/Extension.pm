# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::RequestNagger;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;

our $VERSION = '1';

#
# installation
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'nag_watch'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            nagged_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            watcher_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
        ],
        INDEXES => [
            nag_watch_idx => {
                FIELDS => [ 'nagged_id', 'watcher_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'nag_defer'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            flag_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'flags',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                }
            },
            defer_until => {
                TYPE    => 'DATETIME',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            nag_defer_idx => {
                FIELDS => [ 'flag_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_add_column('products', 'nag_interval', { TYPE => 'INT2',  NOTNULL => 1, DEFAULT => 7 * 24  });
}

__PACKAGE__->NAME;
