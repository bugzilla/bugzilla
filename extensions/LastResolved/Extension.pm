# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::LastResolved;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla::Bug qw(LogActivityEntry);
use Bugzilla::Util qw(format_time);
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Install::Util qw(indicate_progress);

our $VERSION = '0.01';

sub install_update_db {
    my ($self, $args) = @_;
    my $last_resolved = Bugzilla::Field->new({'name' => 'cf_last_resolved'});
    if (!$last_resolved) {
        Bugzilla::Field->create({
            name        => 'cf_last_resolved',
            description => 'Last Resolved',
            type        => FIELD_TYPE_DATETIME,
            mailhead    => 0,
            enter_bug   => 0,
            obsolete    => 0,
            custom      => 1,
            buglist     => 1,
        });
        _migrate_last_resolved();
    }
}

sub _migrate_last_resolved {
    my $dbh = Bugzilla->dbh;
    my $field_id = get_field_id('bug_status');
    my $resolved_activity = $dbh->selectall_arrayref(
        "SELECT bugs_activity.bug_id, bugs_activity.bug_when, bugs_activity.who 
           FROM bugs_activity
          WHERE bugs_activity.fieldid = ?
                AND bugs_activity.added = 'RESOLVED'
          ORDER BY bugs_activity.bug_when",
        undef, $field_id);

    my $count = 1;
    my $total = scalar @$resolved_activity;
    my %current_last_resolved;
    foreach my $activity (@$resolved_activity) {
        indicate_progress({ current => $count++, total => $total, every => 25 });
        my ($id, $new, $who) = @$activity;
        my $old = $current_last_resolved{$id} ? $current_last_resolved{$id} : "";
        $dbh->do("UPDATE bugs SET cf_last_resolved = ? WHERE bug_id = ?", undef, $new, $id);
        LogActivityEntry($id, 'cf_last_resolved', $old, $new, $who, $new);
        $current_last_resolved{$id} = $new;
    }
}

sub active_custom_fields {
    my ($self, $args) = @_;
    my $fields = $args->{'fields'};
    my @tmp_fields = grep($_->name ne 'cf_last_resolved', @$$fields);
    $$fields = \@tmp_fields;
}

sub bug_end_of_update {
    my ($self, $args) = @_;
    my $dbh = Bugzilla->dbh;
    my ($bug, $old_bug, $timestamp, $changes) =
        @$args{qw(bug old_bug timestamp changes)};
    if ($changes->{'bug_status'}) {
        # If the bug has been resolved then update the cf_last_resolved
        # value to the current timestamp if cf_last_resolved exists
        if ($bug->bug_status eq 'RESOLVED') {
            $dbh->do("UPDATE bugs SET cf_last_resolved = ? WHERE bug_id = ?",
                     undef, $timestamp, $bug->id);
            my $old_value = $bug->cf_last_resolved || '';
            LogActivityEntry($bug->id, 'cf_last_resolved', $old_value,
                             $timestamp, Bugzilla->user->id, $timestamp);
        }
    }
}

sub bug_fields {
    my ($self, $args) = @_;
    my $fields = $args->{'fields'};
    push (@$fields, 'cf_last_resolved')
}

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::Bug')) {
        push(@$columns, 'cf_last_resolved');
    }
}

sub buglist_columns {
    my ($self,  $args) = @_;
    my $columns = $args->{columns};
    $columns->{'cf_last_resolved'} = {
         name  => 'bugs.cf_last_resolved', 
         title => 'Last Resolved', 
    };
}

__PACKAGE__->NAME;
