# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::RequestNagger::Constants;

use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);

our @EXPORT = qw(
  MAX_SETTER_COUNT
  MAX_REQUEST_AGE
  FLAG_TYPES
  REQUESTEE_NAG_SQL
  SETTER_NAG_SQL
  WATCHING_REQUESTEE_NAG_SQL
  WATCHING_SETTER_NAG_SQL
);

# if there are more than this many requests that a user is waiting on, show a
# summary and a link instead
use constant MAX_SETTER_COUNT => 7;

# ignore any request older than this many days in the requestee emails
# massively overdue requests will still be included in the 'watching' emails
use constant MAX_REQUEST_AGE => 90;    # about three months

# the order of this array determines the order used in email
use constant FLAG_TYPES => (
  {
    type => 'review',                  # flag_type.name
    group => 'everyone', # the user must be a member of this group to receive reminders
  },
  {type => 'superview', group => 'everyone',},
  {type => 'feedback',  group => 'everyone',},
  {type => 'needinfo',  group => 'editbugs',},
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
        setter.userid AS setter_id,
        requestee.userid AS requestee_id,
        flags.requestee_id AS recipient_id,
        flags.requestee_id AS target_id,
        products.nag_interval,
        0 AS extended_period
    FROM
        flags
        INNER JOIN flagtypes ON flagtypes.id = flags.type_id
        INNER JOIN profiles AS setter ON setter.userid = flags.setter_id
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
        AND TIMESTAMPDIFF(DAY, flags.modification_date, CURRENT_DATE()) <= "
    . MAX_REQUEST_AGE . "
        AND (profile_setting.setting_value IS NULL OR profile_setting.setting_value = 'on')
        AND requestee.disable_mail = 0
        AND nag_defer.id IS NULL
    ORDER BY
        flags.requestee_id,
        flagtypes.name,
        flags.modification_date
    ";
}

sub SETTER_NAG_SQL {
  my $dbh = Bugzilla->dbh;
  my @flag_types_sql = map { $dbh->quote($_->{type}) } FLAG_TYPES;

  return "
    SELECT
        flagtypes.name AS flag_type,
        flags.id AS flag_id,
        flags.bug_id,
        flags.attach_id,
        flags.modification_date,
        setter.userid AS setter_id,
        requestee.userid AS requestee_id,
        flags.setter_id AS recipient_id,
        flags.setter_id AS target_id,
        products.nag_interval,
        0 AS extended_period
    FROM
        flags
        INNER JOIN flagtypes ON flagtypes.id = flags.type_id
        INNER JOIN profiles AS setter ON setter.userid = flags.setter_id
        LEFT JOIN profiles AS requestee ON requestee.userid = flags.requestee_id
        INNER JOIN bugs ON bugs.bug_id = flags.bug_id
        INNER JOIN products ON products.id = bugs.product_id
        LEFT JOIN attachments ON attachments.attach_id = flags.attach_id
        LEFT JOIN profile_setting ON profile_setting.setting_name = 'request_nagging'
                  AND profile_setting.user_id = flags.setter_id
        LEFT JOIN nag_defer ON nag_defer.flag_id = flags.id
    WHERE
        " . $dbh->sql_in('flagtypes.name', \@flag_types_sql) . "
        AND flags.status = '?'
        AND products.nag_interval != 0
        AND TIMESTAMPDIFF(HOUR, flags.modification_date, CURRENT_DATE()) >= products.nag_interval
        AND TIMESTAMPDIFF(DAY, flags.modification_date, CURRENT_DATE()) <= "
    . MAX_REQUEST_AGE . "
        AND (profile_setting.setting_value IS NULL OR profile_setting.setting_value = 'on')
        AND setter.disable_mail = 0
        AND nag_defer.id IS NULL
    ORDER BY
        flags.setter_id,
        flagtypes.name,
        flags.modification_date
    ";
}

sub WATCHING_REQUESTEE_NAG_SQL {
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
        setter.userid AS setter_id,
        requestee.userid AS requestee_id,
        nag_watch.watcher_id AS recipient_id,
        requestee.userid AS target_id,
        products.nag_interval,
        COALESCE(extended_period.setting_value, 0) AS extended_period
    FROM
        flags
        INNER JOIN flagtypes ON flagtypes.id = flags.type_id
        INNER JOIN profiles AS setter ON setter.userid = flags.setter_id
        INNER JOIN profiles AS requestee ON requestee.userid = flags.requestee_id
        INNER JOIN bugs ON bugs.bug_id = flags.bug_id
        INNER JOIN products ON products.id = bugs.product_id
        LEFT JOIN attachments ON attachments.attach_id = flags.attach_id
        LEFT JOIN nag_defer ON nag_defer.flag_id = flags.id
        INNER JOIN nag_watch ON nag_watch.nagged_id = flags.requestee_id
        INNER JOIN profiles AS watcher ON watcher.userid = nag_watch.watcher_id
        LEFT JOIN nag_settings AS reviews_only ON reviews_only.user_id = nag_watch.watcher_id
            AND reviews_only.setting_name = 'reviews_only'
        LEFT JOIN nag_settings AS extended_period ON extended_period.user_id = nag_watch.watcher_id
            AND extended_period.setting_name = 'extended_period'
    WHERE
        flags.status = '?'
        AND products.nag_interval != 0
        AND watcher.disable_mail = 0
        AND CASE WHEN COALESCE(reviews_only.setting_value, 0) = 1
            THEN flagtypes.name = 'review'
            ELSE " . $dbh->sql_in('flagtypes.name', \@flag_types_sql) . "
        END
        AND CASE WHEN COALESCE(extended_period.setting_value, 0) = 1
            THEN TIMESTAMPDIFF(HOUR, flags.modification_date, CURRENT_DATE()) >= products.nag_interval + 24
            ELSE TIMESTAMPDIFF(HOUR, flags.modification_date, CURRENT_DATE()) >= products.nag_interval
        END
    ORDER BY
        nag_watch.watcher_id,
        flags.requestee_id,
        flags.modification_date
    ";
}

sub WATCHING_SETTER_NAG_SQL {
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
        setter.userid AS setter_id,
        requestee.userid AS requestee_id,
        nag_watch.watcher_id AS recipient_id,
        setter.userid AS target_id,
        products.nag_interval,
        COALESCE(extended_period.setting_value, 0) AS extended_period
    FROM
        flags
        INNER JOIN flagtypes ON flagtypes.id = flags.type_id
        INNER JOIN profiles AS setter ON setter.userid = flags.setter_id
        LEFT JOIN profiles AS requestee ON requestee.userid = flags.requestee_id
        INNER JOIN bugs ON bugs.bug_id = flags.bug_id
        INNER JOIN products ON products.id = bugs.product_id
        LEFT JOIN attachments ON attachments.attach_id = flags.attach_id
        LEFT JOIN nag_defer ON nag_defer.flag_id = flags.id
        INNER JOIN nag_watch ON nag_watch.nagged_id = flags.setter_id
        INNER JOIN profiles AS watcher ON watcher.userid = nag_watch.watcher_id
        LEFT JOIN nag_settings AS reviews_only ON reviews_only.user_id = nag_watch.watcher_id
            AND reviews_only.setting_name = 'reviews_only'
        LEFT JOIN nag_settings AS extended_period ON extended_period.user_id = nag_watch.watcher_id
            AND extended_period.setting_name = 'extended_period'
    WHERE
        flags.status = '?'
        AND products.nag_interval != 0
        AND watcher.disable_mail = 0
        AND CASE WHEN COALESCE(reviews_only.setting_value, 0) = 1
            THEN flagtypes.name = 'review'
            ELSE " . $dbh->sql_in('flagtypes.name', \@flag_types_sql) . "
        END
        AND CASE WHEN COALESCE(extended_period.setting_value, 0) = 1
            THEN TIMESTAMPDIFF(HOUR, flags.modification_date, CURRENT_DATE()) >= products.nag_interval + 24
            ELSE TIMESTAMPDIFF(HOUR, flags.modification_date, CURRENT_DATE()) >= products.nag_interval
        END
    ORDER BY
        nag_watch.watcher_id,
        flags.requestee_id,
        flags.modification_date
    ";
}

1;
