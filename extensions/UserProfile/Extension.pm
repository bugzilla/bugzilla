# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::UserProfile;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Extension::UserProfile::Util;
use Bugzilla::Install::Filesystem;
use Bugzilla::User;

our $VERSION = '1';

#
# installation
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'profiles_statistics'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            name => {
                TYPE    => 'VARCHAR(30)',
                NOTNULL => 1,
            },
            count => {
                TYPE    => 'INT',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            profiles_statistics_name_idx => {
                FIELDS => [ 'user_id', 'name' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'profiles_statistics_status'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            status => {
                TYPE    => 'VARCHAR(64)',
                NOTNULL => 1,
            },
            count => {
                TYPE    => 'INT',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            profiles_statistics_status_idx => {
                FIELDS => [ 'user_id', 'status' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'profiles_statistics_products'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            product => {
                TYPE    => 'VARCHAR(64)',
                NOTNULL => 1,
            },
            count => {
                TYPE    => 'INT',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            profiles_statistics_products_idx => {
                FIELDS => [ 'user_id', 'product' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_add_column('profiles', 'last_activity_ts', { TYPE => 'DATETIME' });
    $dbh->bz_add_column('profiles', 'last_statistics_ts', { TYPE => 'DATETIME' });
}

__PACKAGE__->NAME;
