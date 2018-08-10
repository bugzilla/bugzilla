# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Test::MockDB;
use 5.10.1;
use strict;
use warnings;
use Try::Tiny;
use Capture::Tiny qw(capture_merged);

use Bugzilla::Test::MockLocalconfig (
    db_driver => 'sqlite',
    db_name => ':memory:',
);
use Bugzilla;
BEGIN { Bugzilla->extensions };
use Bugzilla::Test::MockParams;

sub import {
    require Bugzilla::Install;
    require Bugzilla::Install::DB;
    require Bugzilla::Field;;

    state $first_time = 0;

    return undef if $first_time++;

    return capture_merged {
        Bugzilla->dbh->bz_setup_database();

        # Populate the tables that hold the values for the <select> fields.
        Bugzilla->dbh->bz_populate_enum_tables();

        Bugzilla::Install::DB::update_fielddefs_definition();
        Bugzilla::Field::populate_field_definitions();
        Bugzilla::Install::init_workflow();
        Bugzilla::Install::DB->update_table_definitions({});
        Bugzilla::Install::update_system_groups();

        Bugzilla->set_user(Bugzilla::User->super_user);

        Bugzilla::Install::update_settings();
    };
}

1;
