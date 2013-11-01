# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::RequestNagger::Constants;

use strict;
use base qw(Exporter);

our @EXPORT = qw(
    FLAG_TYPES
    REQUESTEE_NAG_SQL
    WATCHING_NAG_SQL
);

# the order of this array determines the order used in email
use constant FLAG_TYPES => (
    {
        type    => 'review',    # flag_type.name
        group   => 'everyone',  # the user must be a member of this group to receive reminders
    },
    {
        type    => 'feedback',
        group   => 'everyone',
    },
    {
        type    => 'needinfo',
        group   => 'editbugs',
    },
);

sub REQUESTEE_NAG_SQL {
    my $dbh = Bugzilla->dbh;
    my @flag_types_sql = map { $dbh->quote($_->{type}) } FLAG_TYPES;

    return "
    SELECT
        flagtypes.name AS flag_type,
        flags.id AS flag_id,
        flags.bug_id,
        flags.attach_id,
        flags.modification_date,
        requester.userid AS requester_id,
        requestee.userid AS requestee_id
    FROM
        flags
        INNER JOIN flagtypes ON flagtypes.id = flags.type_id
        INNER JOIN profiles AS requester ON requester.userid = flags.setter_id
        INNER JOIN profiles AS requestee ON requestee.userid = flags.requestee_id
        INNER JOIN bugs ON bugs.bug_id = flags.bug_id
        INNER JOIN products ON products.id = bugs.product_id
        LEFT JOIN attachments ON attachments.attach_id = flags.attach_id
        LEFT JOIN profile_setting ON profile_setting.setting_name = 'request_nagging'
                  AND profile_setting.user_id = flags.requestee_id
        LEFT JOIN nag_defer ON nag_defer.flag_id = flags.id
    WHERE
        " . $dbh->sql_in('flagtypes.name', \@flag_types_sql) . "
        AND flags.status = '?'
        AND products.nag_interval != 0
        AND TIMESTAMPDIFF(HOUR, flags.modification_date, CURRENT_DATE()) >= products.nag_interval
        AND (profile_setting.setting_value IS NULL OR profile_setting.setting_value = 'on')
        AND requestee.disable_mail = 0
        AND nag_defer.id IS NULL
    ORDER BY
        flags.requestee_id,
        flagtypes.name,
        flags.modification_date
    ";
}

sub WATCHING_NAG_SQL {
    my $dbh = Bugzilla->dbh;
    my @flag_types_sql = map { $dbh->quote($_->{type}) } FLAG_TYPES;

    return "
    SELECT
        nag_watch.watcher_id,
        flagtypes.name AS flag_type,
        flags.id AS flag_id,
        flags.bug_id,
        flags.attach_id,
        flags.modification_date,
        requester.userid AS requester_id,
        requestee.userid AS requestee_id
    FROM
        flags
        INNER JOIN flagtypes ON flagtypes.id = flags.type_id
        INNER JOIN profiles AS requester ON requester.userid = flags.setter_id
        INNER JOIN profiles AS requestee ON requestee.userid = flags.requestee_id
        INNER JOIN bugs ON bugs.bug_id = flags.bug_id
        INNER JOIN products ON products.id = bugs.product_id
        LEFT JOIN attachments ON attachments.attach_id = flags.attach_id
        LEFT JOIN nag_defer ON nag_defer.flag_id = flags.id
        INNER JOIN nag_watch ON nag_watch.nagged_id = flags.requestee_id
        INNER JOIN profiles AS watcher ON watcher.userid = nag_watch.watcher_id
    WHERE
        " . $dbh->sql_in('flagtypes.name', \@flag_types_sql) . "
        AND flags.status = '?'
        AND products.nag_interval != 0
        AND TIMESTAMPDIFF(HOUR, flags.modification_date, CURRENT_DATE()) >= products.nag_interval
        AND watcher.disable_mail = 0
    ORDER BY
        nag_watch.watcher_id,
        flags.requestee_id,
        flags.modification_date
    ";
}

1;
