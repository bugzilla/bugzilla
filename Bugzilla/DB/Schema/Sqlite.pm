# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>

use strict;
package Bugzilla::DB::Schema::Sqlite;
use base qw(Bugzilla::DB::Schema);

use Bugzilla::Error;

use Storable qw(dclone);

use constant FK_ON_CREATE => 1;

sub _initialize {

    my $self = shift;

    $self = $self->SUPER::_initialize(@_);

    $self->{db_specific} = {
        BOOLEAN =>      'integer',
        FALSE =>        '0', 
        TRUE =>         '1',

        INT1 =>         'integer',
        INT2 =>         'integer',
        INT3 =>         'integer',
        INT4 =>         'integer',

        SMALLSERIAL =>  'SERIAL',
        MEDIUMSERIAL => 'SERIAL',
        INTSERIAL =>    'SERIAL',

        TINYTEXT =>     'text',
        MEDIUMTEXT =>   'text',
        LONGTEXT =>     'text',

        LONGBLOB =>     'blob',

        DATETIME =>     'DATETIME',
    };

    $self->_adjust_schema;

    return $self;

}

sub get_type_ddl {
    my $self = shift;
    my $def = dclone($_[0]);
    
    my $ddl = $self->SUPER::get_type_ddl(@_);
    if ($def->{PRIMARYKEY} and $def->{TYPE} eq 'SERIAL') {
        $ddl =~ s/\bSERIAL\b/integer/;
        $ddl =~ s/\bPRIMARY KEY\b/PRIMARY KEY AUTOINCREMENT/;
    }
    if ($def->{TYPE} =~ /text/i or $def->{TYPE} =~ /char/i) {
        $ddl .= " COLLATE bugzilla";
    }
    # Don't collate DATETIME fields.
    if ($def->{TYPE} eq 'DATETIME') {
        $ddl =~ s/\bDATETIME\b/text COLLATE BINARY/;
    }
    return $ddl;
}

1;
