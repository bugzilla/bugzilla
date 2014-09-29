# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::UserActivity;
use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::Extension::BMO::Util;
use Bugzilla::User;
use Bugzilla::Util qw(trim);
use DateTime;

sub report {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;

    my @who = ();
    my $from = trim($input->{'from'} || '');
    my $to = trim($input->{'to'} || '');
    my $action = $input->{'action'} || '';

    # fix non-breaking hyphens
    $from =~ s/\N{U+2011}/-/g;
    $to =~ s/\N{U+2011}/-/g;

    if ($from eq '') {
        my $dt = DateTime->now()->subtract('weeks' => 1);
        $from = $dt->ymd('-');
    }
    if ($to eq '') {
        my $dt = DateTime->now();
        $to = $dt->ymd('-');
    }

    if ($action eq 'run') {
        if (!exists $input->{'who'} || $input->{'who'} eq '') {
            ThrowUserError('user_activity_missing_username');
        }
        Bugzilla::User::match_field({ 'who' => {'type' => 'multi'} });

        my $from_dt = string_to_datetime($from);
        $from = $from_dt->ymd();

        my $to_dt = string_to_datetime($to);
        $to = $to_dt->ymd();
        # add one day to include all activity that happened on the 'to' date
        $to_dt->add(days => 1);

        my ($activity_joins, $activity_where) = ('', '');
        my ($attachments_joins, $attachments_where) = ('', '');
        my ($tags_activity_joins, $tags_activity_where) = ('', '');
        if (Bugzilla->params->{"insidergroup"}
            && !Bugzilla->user->in_group(Bugzilla->params->{'insidergroup'}))
        {
            $activity_joins = "LEFT JOIN attachments
                       ON attachments.attach_id = bugs_activity.attach_id";
            $activity_where = "AND COALESCE(attachments.isprivate, 0) = 0";
            $attachments_where = $activity_where;

            $tags_activity_joins = 'LEFT JOIN longdescs
                ON longdescs_tags_activity.comment_id = longdescs.comment_id';
            $tags_activity_where = 'AND COALESCE(longdescs.isprivate, 0) = 0';
        }

        my @who_bits;
        foreach my $who (
            ref $input->{'who'}
            ? @{$input->{'who'}}
            : $input->{'who'}
        ) {
            push @who, $who;
            push @who_bits, '?';
        }
        my $who_bits = join(',', @who_bits);

        if (!@who) {
            my $template = Bugzilla->template;
            my $cgi = Bugzilla->cgi;
            my $vars = {};
            $vars->{'script'}        = $cgi->url(-relative => 1);
            $vars->{'fields'}        = {};
            $vars->{'matches'}       = [];
            $vars->{'matchsuccess'}  = 0;
            $vars->{'matchmultiple'} = 1;
            print $cgi->header();
            $template->process("global/confirm-user-match.html.tmpl", $vars)
              || ThrowTemplateError($template->error());
            exit;
        }

        $from_dt = $from_dt->ymd() . ' 00:00:00';
        $to_dt = $to_dt->ymd() . ' 23:59:59';
        my @params;
        for (1..5) {
            push @params, @who;
            push @params, ($from_dt, $to_dt);
        }

        my $order = ($input->{'sort'} && $input->{'sort'} eq 'bug')
                    ? 'bug_id, bug_when' : 'bug_when';

        my $comment_filter = '';
        if (!Bugzilla->user->is_insider) {
            $comment_filter = 'AND longdescs.isprivate = 0';
        }

        my $query = "
        SELECT
                   fielddefs.name,
                   bugs_activity.bug_id,
                   bugs_activity.attach_id,
                   ".$dbh->sql_date_format('bugs_activity.bug_when', '%Y.%m.%d %H:%i:%s')." AS ts,
                   bugs_activity.removed,
                   bugs_activity.added,
                   profiles.login_name,
                   bugs_activity.comment_id,
                   bugs_activity.bug_when
              FROM bugs_activity
                   $activity_joins
         LEFT JOIN fielddefs
                ON bugs_activity.fieldid = fielddefs.id
        INNER JOIN profiles
                ON profiles.userid = bugs_activity.who
             WHERE profiles.login_name IN ($who_bits)
                   AND bugs_activity.bug_when >= ? AND bugs_activity.bug_when <= ?
                   $activity_where

        UNION ALL

        SELECT
                   'comment_tag' AS name,
                   longdescs_tags_activity.bug_id,
                   NULL as attach_id,
                   ".$dbh->sql_date_format('longdescs_tags_activity.bug_when',
                       '%Y.%m.%d %H:%i:%s') . " AS bug_when,
                   longdescs_tags_activity.removed,
                   longdescs_tags_activity.added,
                   profiles.login_name,
                   longdescs_tags_activity.comment_id,
                   longdescs_tags_activity.bug_when
              FROM longdescs_tags_activity
                   $tags_activity_joins
        INNER JOIN profiles
                ON profiles.userid = longdescs_tags_activity.who
             WHERE profiles.login_name IN ($who_bits)
                   AND longdescs_tags_activity.bug_when >= ?
                   AND longdescs_tags_activity.bug_when <= ?
                  $tags_activity_where

        UNION ALL

        SELECT
                   'bug_id' AS name,
                   bugs.bug_id,
                   NULL AS attach_id,
                   ".$dbh->sql_date_format('bugs.creation_ts', '%Y.%m.%d %H:%i:%s')." AS ts,
                   '(new bug)' AS removed,
                   bugs.short_desc AS added,
                   profiles.login_name,
                   NULL AS comment_id,
                   bugs.creation_ts AS bug_when
              FROM bugs
        INNER JOIN profiles
                ON profiles.userid = bugs.reporter
             WHERE profiles.login_name IN ($who_bits)
                   AND bugs.creation_ts >= ? AND bugs.creation_ts <= ?

        UNION ALL

        SELECT
                   'longdesc' AS name,
                   longdescs.bug_id,
                   NULL AS attach_id,
                   DATE_FORMAT(longdescs.bug_when, '%Y.%m.%d %H:%i:%s') AS ts,
                   '' AS removed,
                   '' AS added,
                   profiles.login_name,
                   longdescs.comment_id AS comment_id,
                   longdescs.bug_when
              FROM longdescs
        INNER JOIN profiles
                ON profiles.userid = longdescs.who
             WHERE profiles.login_name IN ($who_bits)
                   AND longdescs.bug_when >= ? AND longdescs.bug_when <= ?
                   $comment_filter

        UNION ALL

        SELECT
                   'attachments.description' AS name,
                   attachments.bug_id,
                   attachments.attach_id,
                   ".$dbh->sql_date_format('attachments.creation_ts', '%Y.%m.%d %H:%i:%s')." AS ts,
                   '(new attachment)' AS removed,
                   attachments.description AS added,
                   profiles.login_name,
                   NULL AS comment_id,
                   attachments.creation_ts AS bug_when
              FROM attachments
        INNER JOIN profiles
                ON profiles.userid = attachments.submitter_id
             WHERE profiles.login_name IN ($who_bits)
                   AND attachments.creation_ts >= ? AND attachments.creation_ts <= ?
                   $attachments_where

          ORDER BY $order ";

        my $list = $dbh->selectall_arrayref($query, undef, @params);

        if ($input->{debug}) {
            while (my $param = shift @params) {
                $query =~ s/\?/$dbh->quote($param)/e;
            }
            $vars->{debug_sql} = $query;
        }

        my @operations;
        my $operation = {};
        my $changes = [];
        my $incomplete_data = 0;
        my %bug_ids;

        foreach my $entry (@$list) {
            my ($fieldname, $bugid, $attachid, $when, $removed, $added, $who,
                $comment_id) = @$entry;
            my %change;
            my $activity_visible = 1;

            next unless Bugzilla->user->can_see_bug($bugid);

            # check if the user should see this field's activity
            if ($fieldname eq 'remaining_time'
                || $fieldname eq 'estimated_time'
                || $fieldname eq 'work_time'
                || $fieldname eq 'deadline')
            {
                $activity_visible = Bugzilla->user->is_timetracker;
            }
            elsif ($fieldname eq 'longdescs.isprivate'
                    && !Bugzilla->user->is_insider
                    && $added)
            {
                $activity_visible = 0;
            }
            else {
                $activity_visible = 1;
            }

            if ($activity_visible) {
                # Check for the results of an old Bugzilla data corruption bug
                if (($added eq '?' && $removed eq '?')
                    || ($added =~ /^\? / || $removed =~ /^\? /)) {
                    $incomplete_data = 1;
                }

                # Start a new changeset if required (depends on the sort order)
                my $is_new_changeset;
                if ($order eq 'bug_when') {
                    $is_new_changeset =
                        $operation->{'who'} &&
                        (
                            $who ne $operation->{'who'}
                            || $when ne $operation->{'when'}
                            || $bugid != $operation->{'bug'}
                        );
                } else {
                    $is_new_changeset =
                        $operation->{'bug'} &&
                        $bugid != $operation->{'bug'};
                }
                if ($is_new_changeset) {
                    $operation->{'changes'} = $changes;
                    push (@operations, $operation);
                    $operation = {};
                    $changes = [];
                }

                $bug_ids{$bugid} = 1;

                $operation->{'bug'} = $bugid;
                $operation->{'who'} = $who;
                $operation->{'when'} = $when;

                $change{'fieldname'} = $fieldname;
                $change{'attachid'} = $attachid;
                $change{'removed'} = $removed;
                $change{'added'} = $added;
                $change{'when'} = $when;

                if ($comment_id) {
                    $change{'comment'} = Bugzilla::Comment->new($comment_id);
                    next if $change{'comment'}->count == 0;
                }

                if ($attachid) {
                    $change{'attach'} = Bugzilla::Attachment->new($attachid);
                }

                push (@$changes, \%change);
            }
        }

        if ($operation->{'who'}) {
            $operation->{'changes'} = $changes;
            push (@operations, $operation);
        }

        $vars->{'incomplete_data'} = $incomplete_data;
        $vars->{'operations'} = \@operations;

        my @bug_ids = sort { $a <=> $b } keys %bug_ids;
        $vars->{'bug_ids'} = \@bug_ids;
    }

    $vars->{'action'} = $action;
    $vars->{'who'} = join(',', @who);
    $vars->{'who_count'} = scalar @who;
    $vars->{'from'} = $from;
    $vars->{'to'} = $to;
    $vars->{'sort'} = $input->{'sort'};
}

1;
