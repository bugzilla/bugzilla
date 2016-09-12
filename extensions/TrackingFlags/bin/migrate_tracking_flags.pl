#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Migrate old custom field based tracking flags to the new
# table based tracking flags

use strict;
use warnings;

use FindBin '$RealBin';
use lib "$RealBin/../../..";
use lib "$RealBin/../../../lib";
use lib "$RealBin/../lib";

BEGIN {
    use Bugzilla;
    Bugzilla->extensions;
}

use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Product;
use Bugzilla::Component;
use Bugzilla::Extension::BMO::Data;
use Bugzilla::Install::Util qw(indicate_progress);

use Bugzilla::Extension::TrackingFlags::Constants;
use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::Extension::TrackingFlags::Flag::Bug;
use Bugzilla::Extension::TrackingFlags::Flag::Value;
use Bugzilla::Extension::TrackingFlags::Flag::Visibility;

use Getopt::Long;
use Data::Dumper;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($dry_run, $trace) = (0, 0);
GetOptions(
    "dry-run" => \$dry_run,
    "trace"   => \$trace,
) or exit;

my $dbh = Bugzilla->dbh;

$dbh->{TraceLevel} = 1 if $trace;

my %product_cache;
my %component_cache;

sub migrate_flag_visibility {
    my ($new_flag, $products) = @_;

    # Create product/component visibility
    foreach my $prod_name (keys %$products) {
        $product_cache{$prod_name} ||= Bugzilla::Product->new({ name => $prod_name });
        if (!$product_cache{$prod_name}) {
            warn "No such product $prod_name\n";
            next;
        }

        # If no components specified then we do Product/__any__
        # otherwise, we enter an entry for each Product/Component
        my $components = $products->{$prod_name};
        if (!@$components) {
            Bugzilla::Extension::TrackingFlags::Flag::Visibility->create({
                tracking_flag_id => $new_flag->flag_id,
                product_id       => $product_cache{$prod_name}->id,
                component_id     => undef
            });
        }
        else {
            foreach my $comp_name (@$components) {
                my $comp_matches = [];
                # If the component is a regexp, we need to find all components
                # matching the regex and insert each individually
                if (ref $comp_name eq 'Regexp') {
                    my $comp_re = $comp_name;
                    $comp_re =~ s/\?\-xism://;
                    $comp_re =~ s/\(//;
                    $comp_re =~ s/\)//;
                    $comp_matches = $dbh->selectcol_arrayref(
                        'SELECT components.name FROM components
                          WHERE components.product_id = ?
                                AND ' . $dbh->sql_regexp('components.name', $dbh->quote($comp_re)) . '
                          ORDER BY components.name',
                        undef,
                        $product_cache{$prod_name}->id);
                }
                else {
                    $comp_matches = [ $comp_name ];
                }

                foreach my $comp_match (@$comp_matches) {
                    $component_cache{"${prod_name}:${comp_match}"}
                        ||= Bugzilla::Component->new({ name    => $comp_match,
                                                       product => $product_cache{$prod_name} });
                    if (!$component_cache{"${prod_name}:${comp_match}"}) {
                        warn "No such product $prod_name and component $comp_match\n";
                        next;
                    }

                    Bugzilla::Extension::TrackingFlags::Flag::Visibility->create({
                        tracking_flag_id => $new_flag->flag_id,
                        product_id       => $product_cache{$prod_name}->id,
                        component_id     => $component_cache{"${prod_name}:${comp_match}"}->id,
                    });
                }
            }
        }
    }
}

sub migrate_flag_values {
    my ($new_flag, $field) = @_;

    print "Migrating flag values...";

    my %blocking_trusted_requesters
        = %{$Bugzilla::Extension::BMO::Data::blocking_trusted_requesters};
    my %blocking_trusted_setters
        = %{$Bugzilla::Extension::BMO::Data::blocking_trusted_setters};
    my %status_trusted_wanters
        = %{$Bugzilla::Extension::BMO::Data::status_trusted_wanters};
    my %status_trusted_setters
        = %{$Bugzilla::Extension::BMO::Data::status_trusted_setters};

    my %group_cache;
    foreach my $value (@{ $field->legal_values }) {
        my $group_name = 'everyone';

        if ($field->name =~ /^cf_(blocking|tracking)_/) {
            if ($value->name ne '---' && $value->name !~ '\?$') {
                $group_name = get_setter_group($field->name, \%blocking_trusted_setters);
            }
            if ($value->name eq '?') {
                $group_name = get_setter_group($field->name, \%blocking_trusted_requesters);
            }
        } elsif ($field->name =~ /^cf_status_/) {
            if ($value->name eq 'wanted') {
                $group_name = get_setter_group($field->name, \%status_trusted_wanters);
            } elsif ($value->name ne '---' && $value->name ne '?') {
                $group_name = get_setter_group($field->name, \%status_trusted_setters);
            }
        }

        $group_cache{$group_name} ||= Bugzilla::Group->new({ name => $group_name });
        $group_cache{$group_name} || die "Setter group '$group_name' does not exist";

        Bugzilla::Extension::TrackingFlags::Flag::Value->create({
            tracking_flag_id => $new_flag->flag_id,
            value            => $value->name,
            setter_group_id  => $group_cache{$group_name}->id,
            sortkey          => $value->sortkey,
            is_active        => $value->is_active
        });
    }

    print "done.\n";
}

sub get_setter_group {
    my ($field, $trusted) = @_;
    my $setter_group = $trusted->{'_default'} || "";
    foreach my $dfield (keys %$trusted) {
        if ($field =~ $dfield) {
            $setter_group = $trusted->{$dfield};
        }
    }
    return $setter_group;
}

sub migrate_flag_bugs {
    my ($new_flag, $field) = @_;

    print "Migrating bug values...";

    my $bugs = $dbh->selectall_arrayref("SELECT bug_id, " . $field->name . "
                                           FROM bugs
                                          WHERE " . $field->name . " != '---'
                                       ORDER BY bug_id");
    local $| = 1;
    my $count = 1;
    my $total = scalar @$bugs;
    foreach my $row (@$bugs) {
        my ($id, $value) = @$row;
        indicate_progress({ current => $count++, total => $total, every => 25 });
        Bugzilla::Extension::TrackingFlags::Flag::Bug->create({
            tracking_flag_id => $new_flag->flag_id,
            bug_id           => $id,
            value            => $value,

        });
    }

    print "done.\n";
}

sub migrate_flag_activity {
     my ($new_flag, $field) = @_;

     print "Migating flag activity...";

     my $new_field = Bugzilla::Field->new({ name => $new_flag->name });
     $dbh->do("UPDATE bugs_activity SET fieldid = ? WHERE fieldid = ?",
              undef, $new_field->id, $field->id);

     print "done.\n";
}

sub do_migration {
    my $bmo_tracking_flags = $Bugzilla::Extension::BMO::Data::cf_visible_in_products;
    my $bmo_project_flags  = $Bugzilla::Extension::BMO::Data::cf_project_flags;
    my $bmo_disabled_flags = $Bugzilla::Extension::BMO::Data::cf_disabled_flags;

    my $fields = Bugzilla::Field->match({ custom => 1,
                                          type   => FIELD_TYPE_SINGLE_SELECT });

    my @drop_columns;
    foreach my $field (@$fields) {
        next if $field->name !~ /^cf_(blocking|tracking|status)_/;

        foreach my $field_re (keys %$bmo_tracking_flags) {
            next if $field->name !~ $field_re;

            # Create the new tracking flag if not exists
            my $new_flag
                = Bugzilla::Extension::TrackingFlags::Flag->new({ name => $field->name });

            next if $new_flag;

            print "----------------------------------\n" .
                  "Migrating custom tracking field " . $field->name . "...\n";

            my $new_flag_name = $field->name . "_new"; # Temporary name til we delete the old

            my $type = grep($field->name =~ $_, @$bmo_project_flags)
                       ? 'project'
                       : 'tracking';

            my $is_active = grep($_ eq $field->name, @$bmo_disabled_flags) ? 0 : 1;

            $new_flag = Bugzilla::Extension::TrackingFlags::Flag->create({
                 name        => $new_flag_name,
                 description => $field->description,
                 type        => $type,
                 sortkey     => $field->sortkey,
                 is_active   => $is_active,
                 enter_bug   => $field->enter_bug,
            });

            migrate_flag_visibility($new_flag, $bmo_tracking_flags->{$field_re});

            migrate_flag_values($new_flag, $field);

            migrate_flag_bugs($new_flag, $field);

            migrate_flag_activity($new_flag, $field);

            push(@drop_columns, $field->name);

            # Remove the old flag entry from fielddefs
            $dbh->do("DELETE FROM fielddefs WHERE name = ?",
                     undef, $field->name);

            # Rename the new flag
            $dbh->do("UPDATE fielddefs SET name = ? WHERE name = ?",
                     undef, $field->name, $new_flag_name);

            $new_flag->set_name($field->name);
            $new_flag->update;

            # more than one regex could possibly match but we only want the first one
            last;
        }
    }

    # Drop each custom flag's value table and the column from the bz schema object
    if (!$dry_run && @drop_columns) {
        print "Dropping value tables and updating bz schema object...\n";

        foreach my $column (@drop_columns) {
            # Drop the values table
            $dbh->bz_drop_table($column);

            # Drop the bugs table column from the bz schema object
            $dbh->_bz_real_schema->delete_column('bugs', $column);
            $dbh->_bz_store_real_schema;
        }

        # Do the one alter table to drop all columns at once
        $dbh->do("ALTER TABLE bugs DROP COLUMN " . join(", DROP COLUMN ", @drop_columns));
    }
}

# Start Main

eval {
    if ($dry_run) {
        print "** dry run : no changes to the database will be made **\n";
        $dbh->bz_start_transaction();
    }
    print "Starting migration...\n";
    do_migration();
    $dbh->bz_rollback_transaction() if $dry_run;
    print "All done!\n";
};
if ($@) {
    $dbh->bz_rollback_transaction() if $dry_run;
    die "$@" if $@;
}
