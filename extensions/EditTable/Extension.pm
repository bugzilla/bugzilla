# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.


# this is a quick and dirty table editor, designed to allow admins to quickly
# maintain tables.
#
# each table must be defined via the editable_tables hook
#
# this extension doesn't currently provide any ability to modify or validate
# values.  use with caution!

package Bugzilla::Extension::EditTable;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Util qw(trick_taint);
use JSON;
use Storable qw(dclone);

our $VERSION = '1';

# definitions for tables which we can edit with the quick-and-dirty editor
#
# $table_name => {
#   id_field    => name of the "id" field
#   order_by    => the field to sort rows by (optional, defaults to the id_field)
#   blurb       => text which describes the table
#   group       => group required to edit this table (optional, defaults to "admin")
# }
#
# example:
# 'antispam_domain_blocklist' => {
#     id_field   => 'id',
#     order_by   => 'domain',
#     blurb      => 'List of fully qualified domain names to block at account creation time.',
#     group      => 'can_configure_antispam',
# },

sub EDITABLE_TABLES {
    my $tables = {};
    Bugzilla::Hook::process("editable_tables", { tables => $tables });
    return $tables;
}

sub page_before_template {
    my ($self, $args) = @_;
    my ($vars, $page) = @$args{qw(vars page_id)};
    return unless $page eq 'edit_table.html';
    my $input = Bugzilla->input_params;

    # we only support editing a particular set of tables
    my $table_name = $input->{table};
    exists $self->EDITABLE_TABLES()->{$table_name}
        || ThrowUserError('edittable_unsupported', { table => $table_name } );
    my $table = $self->EDITABLE_TABLES()->{$table_name};
    my $id_field = $table->{id_field};
    my $order_by = $table->{order_by} || $id_field;
    my $group    = $table->{group} || 'admin';
    trick_taint($table_name);

    Bugzilla->user->in_group($group)
        || ThrowUserError('auth_failure', { group  => $group,
                                            action => 'edit',
                                            object => 'tables' });

    # load columns
    my $dbh = Bugzilla->dbh;
    my @fields = sort
                 grep { $_ ne $id_field && $_ ne $order_by; }
                 $dbh->bz_table_columns($table_name);
    if ($order_by ne $id_field) {
        unshift @fields, $order_by;
    }

    # update table
    my $data = $input->{table_data};
    my $edits = [];
    if ($data) {
        $data = from_json($data)->{data};
        $edits = dclone($data);
        eval {
            $dbh->bz_start_transaction;

            foreach my $row (@$data) {
                map { trick_taint($_) } @$row;
                if ($row->[0] eq '-') {
                    # add
                    shift @$row;
                    next unless grep { $_ ne '' } @$row;
                    my $placeholders = join(',', split(//, '?' x scalar(@fields)));
                    $dbh->do(
                        "INSERT INTO $table_name(" . join(',', @fields) . ") " .
                        "VALUES ($placeholders)",
                        undef,
                        @$row
                    );
                }
                elsif ($row->[0] < 0) {
                    # delete
                    $dbh->do(
                        "DELETE FROM $table_name WHERE $id_field=?",
                        undef,
                        -$row->[0]
                    );
                }
                else {
                    # update
                    my $id = shift @$row;
                    $dbh->do(
                        "UPDATE $table_name " .
                        "SET " . join(',', map { "$_ = ?" } @fields) . " " .
                        "WHERE $id_field = ?",
                        undef,
                        @$row, $id
                    );
                }
            }

            $dbh->bz_commit_transaction;
            $vars->{updated} = 1;
            $edits = [];
        };
        if ($@) {
            my $error = $@;
            $error =~ s/^DBD::[^:]+::db do failed: //;
            $error =~ s/^(.+) \[for Statement ".+$/$1/s;
            $vars->{error} = $error;
            $dbh->bz_rollback_transaction;
        }
    }

    # load data from table
    unshift @fields, $id_field;
    $data = $dbh->selectall_arrayref(
        "SELECT " . join(',', @fields) . " FROM $table_name ORDER BY $order_by"
    );

    # we don't support nulls currently
    foreach my $row (@$data) {
        if (grep { !defined($_) } @$row) {
            ThrowUserError('edittable_nulls', { table => $table_name } );
        }
    }

    # apply failed edits
    foreach my $edit (@$edits) {
        if ($edit->[0] eq '-') {
            push @$data, $edit;
        }
        else {
            my $id = $edit->[0];
            foreach my $row (@$data) {
                if ($row->[0] == $id) {
                    @$row = @$edit;
                    last;
                }
            }
        }
    }

    $vars->{table_name} = $table_name;
    $vars->{blurb}      = $table->{blurb};
    $vars->{table_data} = to_json({
        fields   => \@fields,
        id_field => $id_field,
        data     => $data,
    });
}

__PACKAGE__->NAME;
