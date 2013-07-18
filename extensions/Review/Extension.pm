# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Review;
use strict;
use warnings;

use base qw(Bugzilla::Extension);
our $VERSION = '1';

use Bugzilla;

#
# installation
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'product_reviewers'} = {
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
            display_name => {
                TYPE    => 'VARCHAR(64)',
            },
            product_id => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'products',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                }
            },
            sortkey => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                DEFAULT => 0,
            },
        ],
        INDEXES => [
            product_reviewers_idx => {
                FIELDS => [ 'user_id', 'product_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'component_reviewers'} = {
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
            display_name => {
                TYPE    => 'VARCHAR(64)',
            },
            component_id => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'components',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                }
            },
            sortkey => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                DEFAULT => 0,
            },
        ],
        INDEXES => [
            component_reviewers_idx => {
                FIELDS => [ 'user_id', 'component_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };

}

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_add_column(
        'products',
        'reviewer_required',
        {
            TYPE    => 'BOOLEAN',
            NOTNULL => 1,
            DEFAULT => 'FALSE',
        }
    );
}

__PACKAGE__->NAME;
