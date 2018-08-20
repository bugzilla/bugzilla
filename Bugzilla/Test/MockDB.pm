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
use Bugzilla::Test::MockParams (
    emailsuffix => '',
    emailregexp => '.+',
);

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

        my $dbh = Bugzilla->dbh;
        if ( !$dbh->selectrow_array("SELECT 1 FROM priority WHERE value = 'P1'") ) {
            $dbh->do("DELETE FROM priority");
            my $count = 100;
            foreach my $priority (map { "P$_" } 1..5) {
                $dbh->do( "INSERT INTO priority (value, sortkey) VALUES (?, ?)", undef, ( $priority, $count + 100 ) );
            }
        }
        my @flagtypes = (
            {
                name             => 'review',
                desc             => 'The patch has passed review by a module owner or peer.',
                is_requestable   => 1,
                is_requesteeble  => 1,
                is_multiplicable => 1,
                grant_group      => '',
                target_type      => 'a',
                cc_list          => '',
                inclusions       => ['']
            },
            {
                name             => 'feedback',
                desc             => 'A particular person\'s input is requested for a patch, ' .
                                    'but that input does not amount to an official review.',
                is_requestable   => 1,
                is_requesteeble  => 1,
                is_multiplicable => 1,
                grant_group      => '',
                target_type      => 'a',
                cc_list          => '',
                inclusions       => ['']
            }
        );

        foreach my $flag (@flagtypes) {
            next if Bugzilla::FlagType->new({ name => $flag->{name} });
            my $grant_group_id = $flag->{grant_group}
                                ? Bugzilla::Group->new({ name => $flag->{grant_group} })->id
                                : undef;
            my $request_group_id = $flag->{request_group}
                                ? Bugzilla::Group->new({ name => $flag->{request_group} })->id
                                : undef;

            $dbh->do('INSERT INTO flagtypes (name, description, cc_list, target_type, is_requestable,
                                            is_requesteeble, is_multiplicable, grant_group_id, request_group_id)
                                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    undef, ($flag->{name}, $flag->{desc}, $flag->{cc_list}, $flag->{target_type},
                            $flag->{is_requestable}, $flag->{is_requesteeble}, $flag->{is_multiplicable},
                            $grant_group_id, $request_group_id));

            my $type_id = $dbh->bz_last_key('flagtypes', 'id');

            foreach my $inclusion (@{$flag->{inclusions}}) {
                my ($product, $component) = split(':', $inclusion);
                my ($prod_id, $comp_id);
                if ($product) {
                    my $prod_obj = Bugzilla::Product->new({ name => $product });
                    $prod_id = $prod_obj->id;
                    if ($component) {
                        $comp_id = Bugzilla::Component->new({ name => $component, product => $prod_obj})->id;
                    }
                }
                $dbh->do('INSERT INTO flaginclusions (type_id, product_id, component_id)
                        VALUES (?, ?, ?)',
                        undef, ($type_id, $prod_id, $comp_id));
            }
        }
    };
}

1;
