# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AntiSpam;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

our $VERSION = '0';

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'antispam_domain_blocklist'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            domain => {
                TYPE    => 'VARCHAR(255)',
                NOTNULL => 1,
            },
            comment => {
                TYPE    => 'VARCHAR(255)',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            antispam_domain_blocklist_idx => {
                FIELDS => [ 'domain' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'antispam_comment_blocklist'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            word => {
                TYPE    => 'VARCHAR(255)',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            antispam_comment_blocklist_idx => {
                FIELDS => [ 'word' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'antispam_ip_blocklist'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            ip_address => {
                TYPE    => 'VARCHAR(15)',
                NOTNULL => 1,
            },
            comment => {
                TYPE    => 'VARCHAR(255)',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            antispam_ip_blocklist_idx => {
                FIELDS => [ 'ip_address' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
}

__PACKAGE__->NAME;
