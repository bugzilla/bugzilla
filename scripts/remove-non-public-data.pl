#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use List::MoreUtils qw(any);
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

# tables/columns not listed in this whitelist will be dropped from the
# database.

my %whitelist = (
    attachments => [qw(
        attach_id bug_id creation_ts modification_time description
        mimetype ispatch filename submitter_id isobsolete attach_size
    )],
    bug_mentors => [qw(
        bug_id user_id
    )],
    bug_see_also => [qw(
        id bug_id value
    )],
    bugs => [qw(
        bug_id assigned_to bug_file_loc bug_severity bug_status
        creation_ts delta_ts short_desc op_sys priority product_id
        rep_platform reporter version component_id resolution
        target_milestone qa_contact status_whiteboard everconfirmed
        estimated_time remaining_time deadline alias cf_rank
        cf_crash_signature cf_last_resolved cf_user_story votes
    )],
    bugs_activity => [qw(
        id bug_id attach_id who bug_when fieldid added removed
        comment_id
    )],
    cc => [qw(
        bug_id who
    )],
    classifications => [qw(
        id name description sortkey
    )],
    components => [qw(
        id name product_id description isactive
    )],
    dependencies => [qw(
        blocked dependson
    )],
    duplicates => [qw(
        dupe_of dupe
    )],
    fielddefs => [qw(
        id name type custom description obsolete
    )],
    flag_state_activity => [qw(
        id flag_when type_id flag_id setter_id requestee_id bug_id
        attachment_id status
    )],
    flags => [qw(
        id type_id status bug_id attach_id creation_date
        modification_date setter_id requestee_id
    )],
    flagtypes => [qw(
        id name description target_type is_active
    )],
    keyworddefs => [qw(
        id name description is_active
    )],
    keywords => [qw(
        bug_id keywordid
    )],
    longdescs => [qw(
        comment_id bug_id who bug_when work_time thetext type
        extra_data
    )],
    longdescs_tags => [qw(
        id comment_id tag
    )],
    longdescs_tags_activity => [qw(
        id bug_id comment_id who bug_when added removed
    )],
    milestones => [qw(
        id product_id value sortkey isactive
    )],
    products => [qw(
        id name classification_id description isactive defaultmilestone
    )],
    profiles => [qw(
        userid login_name realname is_enabled creation_ts
    )],
    tracking_flags => [qw(
        id field_id name description type sortkey is_active
    )],
    tracking_flags_bugs => [qw(
        id tracking_flag_id bug_id value
    )],
    tracking_flags_values => [qw(
        id tracking_flag_id setter_group_id value sortkey is_active
    )],
    versions => [qw(
        id value product_id isactive
    )],
);

#

my $db_name = Bugzilla->localconfig->{db_name};
print <<EOF;
WARNING

This will delete all non public information from the database '$db_name'.

This database will not function as a Bugzilla database once this script has
completed.

Press <Return> to continue, or Ctrl+C to cancel..
EOF
getc();

my $dbh = Bugzilla->dbh;

# run sanitiseme.pl

print "running sanitizeme.pl\n";
system "'$RealBin/sanitizeme.pl' --execute";

if ($dbh->selectrow_array("SELECT COUNT(*) FROM bug_group_map")) {
    die "sanitization failed\n";
}

# drop all views

foreach my $view (sort @{ $dbh->selectcol_arrayref("SHOW FULL TABLES IN $db_name WHERE TABLE_TYPE LIKE 'VIEW'") }) {
    print "dropping view $view\n";
    $dbh->do("DROP VIEW $view");
}

# drop tables/columns

my @tables = map { lc } sort @{ $dbh->selectcol_arrayref("SHOW TABLES") };
foreach my $table (@tables) {
    if (exists $whitelist{$table}) {
        my @drop_columns;
        foreach my $column (map { $_->{Field} } @{ $dbh->selectall_arrayref("DESCRIBE $table", { Slice => {} }) }) {
            unless (any { $_ eq $column } @{ $whitelist{$table} }) {
                print "dropping references to $table.$column\n";
                drop_referencing($table, $column);
                push @drop_columns, "DROP COLUMN $column";
            }
        }
        if (@drop_columns) {
            print "dropping columns from $table\n";
            $dbh->do("ALTER TABLE $table " . join(", ", @drop_columns));
        }
    }
    else {
        print "dropping $table\n";
        drop_referencing($table);
        $dbh->do("DROP TABLE $table");
    }
}

# remove users with no activity

print "deleting users with no activity\n";
$dbh->do("
    DELETE FROM profiles
     WHERE (SELECT COUNT(*) FROM bugs_activity WHERE bugs_activity.who = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM bugs WHERE bugs.reporter = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM bugs WHERE bugs.assigned_to = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM bugs WHERE bugs.qa_contact = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM bugs WHERE bugs.qa_contact = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM longdescs WHERE longdescs.who = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM longdescs_tags_activity WHERE longdescs_tags_activity.who = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM attachments WHERE attachments.submitter_id = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM flags WHERE flags.setter_id = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM flags WHERE flags.requestee_id = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM flag_state_activity WHERE flag_state_activity.setter_id = profiles.userid) = 0
           AND (SELECT COUNT(*) FROM flag_state_activity WHERE flag_state_activity.requestee_id = profiles.userid) = 0
");

sub drop_referencing {
    my ($table, $column) = @_;
    my ($sql, @values);

    # drop foreign keys that reference this table/column
    $sql = "
        SELECT DISTINCT TABLE_NAME 'table', CONSTRAINT_NAME name
          FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
         WHERE CONSTRAINT_SCHEMA = ? AND REFERENCED_TABLE_NAME = ?
    ";
    @values = ($db_name, $table);
    if ($column) {
        $sql .= " AND REFERENCED_COLUMN_NAME = ?";
        push @values, $column;
    }
    foreach my $fk (@{ $dbh->selectall_arrayref($sql, { Slice => {} }, @values) }) {
        print "  dropping fk $fk->{table}.$fk->{name}\n";
        $dbh->do("ALTER TABLE $fk->{table} DROP FOREIGN KEY $fk->{name}");
    }

    # drop indexes
    if ($column) {
        # drop associated fk/index
        $sql = "
            SELECT DISTINCT TABLE_NAME 'table', CONSTRAINT_NAME name, REFERENCED_TABLE_NAME ref
            FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
            WHERE CONSTRAINT_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?
        ";
        @values = ($db_name, $table, $column);
        foreach my $fk (@{ $dbh->selectall_arrayref($sql, { Slice => {} }, @values) }) {
            if ($fk->{ref}) {
                print "  dropping fk $fk->{table}.$fk->{name}\n";
                $dbh->do("ALTER TABLE $fk->{table} DROP FOREIGN KEY $fk->{name}");
            }
            else {
                print "  dropping index $fk->{table}.$fk->{name}\n";
                $dbh->do("ALTER TABLE $fk->{table} DROP INDEX $fk->{name}");
            }
        }

        # drop the index
        my $rows = $dbh->selectall_arrayref(
            "SHOW INDEX FROM $table WHERE Column_name = ?",
            { Slice => {} },
            $column
        );
        foreach my $fk (@$rows) {
            print "  dropping index $fk->{Table}.$fk->{Key_name}\n";
            $dbh->do("ALTER TABLE $fk->{Table} DROP INDEX $fk->{Key_name}");
        }
    }

}

