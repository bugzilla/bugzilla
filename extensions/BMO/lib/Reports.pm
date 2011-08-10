# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with the
# License. You may obtain a copy of the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
# the specific language governing rights and limitations under the License.
#
# The Original Code is the BMO Bugzilla Extension.
#
# The Initial Developer of the Original Code is Byron Jones.  Portions created
# by the Initial Developer are Copyright (C) 2011 the Mozilla Foundation. All
# Rights Reserved.
#
# Contributor(s):
#   Byron Jones <glob@mozilla.com>

package Bugzilla::Extension::BMO::Reports;
use strict;

use Bugzilla::User;
use Bugzilla::Util qw(trim detaint_natural);
use Bugzilla::Error;
use Bugzilla::Constants;

use Date::Parse;
use DateTime;

use base qw(Exporter);

our @EXPORT_OK = qw(user_activity_report
                    triage_reports);

sub user_activity_report {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;

    my @who = ();
    my $from = trim($input->{'from'});
    my $to = trim($input->{'to'});

    if ($input->{'action'} eq 'run') {
        if ($input->{'who'} eq '') {
            ThrowUserError('user_activity_missing_username');
        }
        Bugzilla::User::match_field({ 'who' => {'type' => 'multi'} });

        ThrowUserError('user_activity_missing_from_date') unless $from;
        my $from_time = str2time($from)
            or ThrowUserError('user_activity_invalid_date', { date => $from });
        my $from_dt = DateTime->from_epoch(epoch => $from_time)
                              ->set_time_zone('local')
                              ->truncate(to => 'day');
        $from = $from_dt->ymd();

        ThrowUserError('user_activity_missing_to_date') unless $to;
        my $to_time = str2time($to)
            or ThrowUserError('user_activity_invalid_date', { date => $to });
        my $to_dt = DateTime->from_epoch(epoch => $to_time)
                            ->set_time_zone('local')
                            ->truncate(to => 'day');
        $to = $to_dt->ymd();
        # add one day to include all activity that happened on the 'to' date
        $to_dt->add(days => 1);

        my ($activity_joins, $activity_where) = ('', '');
        my ($attachments_joins, $attachments_where) = ('', '');
        if (Bugzilla->params->{"insidergroup"}
            && !Bugzilla->user->in_group(Bugzilla->params->{'insidergroup'}))
        {
            $activity_joins = "LEFT JOIN attachments
                       ON attachments.attach_id = bugs_activity.attach_id";
            $activity_where = "AND COALESCE(attachments.isprivate, 0) = 0";
            $attachments_where = $activity_where;
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
        for (1..4) {
            push @params, @who;
            push @params, ($from_dt, $to_dt);
        }

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
                   'attachments.filename' AS name,
                   attachments.bug_id,
                   attachments.attach_id,
                   ".$dbh->sql_date_format('attachments.creation_ts', '%Y.%m.%d %H:%i:%s')." AS ts,
                   '' AS removed,
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

          ORDER BY bug_when ";

        my $list = $dbh->selectall_arrayref($query, undef, @params);

        my @operations;
        my $operation = {};
        my $changes = [];
        my $incomplete_data = 0;

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

                # An operation, done by 'who' at time 'when', has a number of
                # 'changes' associated with it.
                # If this is the start of a new operation, store the data from the
                # previous one, and set up the new one.
                if ($operation->{'who'}
                    && ($who ne $operation->{'who'}
                        || $when ne $operation->{'when'}))
                {
                    $operation->{'changes'} = $changes;
                    push (@operations, $operation);
                    $operation = {};
                    $changes = [];
                }

                $operation->{'bug'} = $bugid;
                $operation->{'who'} = $who;
                $operation->{'when'} = $when;

                $change{'fieldname'} = $fieldname;
                $change{'attachid'} = $attachid;
                $change{'removed'} = $removed;
                $change{'added'} = $added;
                
                if ($comment_id) {
                    $change{'comment'} = Bugzilla::Comment->new($comment_id);
                    next if $change{'comment'}->count == 0;
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

    } else {

        if ($from eq '') {
            my ($yy, $mm) = (localtime)[5, 4];
            $from = sprintf("%4d-%02d-01", $yy + 1900, $mm + 1);
        }
        if ($to eq '') {
            my ($yy, $mm, $dd) = (localtime)[5, 4, 3];
            $to = sprintf("%4d-%02d-%02d", $yy + 1900, $mm + 1, $dd);
        }
    }

    $vars->{'action'} = $input->{'action'};
    $vars->{'who'} = join(',', @who);
    $vars->{'from'} = $from;
    $vars->{'to'} = $to;
}

sub triage_reports {
    my ($vars, $filter) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $user = Bugzilla->user;

    if ($input->{'action'} eq 'run' && $input->{'product'}) {

        # load product and components from input

        my $product = Bugzilla::Product->new({ name => $input->{'product'} });

        my @component_ids;
        if ($input->{'component'} ne '') {
            my $ra_components = ref($input->{'component'})
                ? $input->{'component'} : [ $input->{'component'} ];
            foreach my $component_name (@$ra_components) {
                my $component = Bugzilla::Component->new({ name => $component_name, product => $product });
                push @component_ids, $component->id;
            }
        }

        # determine which comment filters to run

        my $filter_commenter = $input->{'filter_commenter'};
        my $filter_commenter_on = $input->{'commenter'};
        my $filter_commenter_id;
        if ($filter_commenter && $filter_commenter_on eq 'is') {
            Bugzilla::User::match_field({ 'commenter_is' => {'type' => 'single'} });
            my $user = Bugzilla::User->new({ name => $input->{'commenter_is'} });
            $filter_commenter_id = $user ? $user->id : 0;
        }

        my $filter_last = $input->{'filter_last'};
        my $filter_last_period = $input->{'last'};
        my $filter_last_time;
        if ($filter_last) {
            if ($filter_last_period eq 'is') {
                $filter_last_period = -1;
                $filter_last_time = str2time($input->{'last_is'} . " 00:00:00") || 0;
            } else {
                detaint_natural($filter_last_period);
                    $filter_last_period = 14 if $filter_last_period < 14;
            }
        }
        my $now = (time);
        $filter_commenter = 1 unless $filter_commenter || $filter_last;

        # form sql queries

        my $bugs_sql = "
              SELECT bug_id, short_desc, reporter, creation_ts
                FROM bugs
               WHERE product_id = ?
                     AND bug_status = 'UNCONFIRMED'";
        if (@component_ids) {
            $bugs_sql .= " AND component_id IN (" . join(',', @component_ids) . ")";
        }
        $bugs_sql .= "
            ORDER BY creation_ts
        ";

        my $comment_count_sql = "
            SELECT COUNT(*)
              FROM longdescs
             WHERE bug_id = ?
        ";

        my $comment_sql = "
              SELECT who, bug_when, type, thetext, extra_data
                FROM longdescs
               WHERE bug_id = ?
        ";
        if (!Bugzilla->user->is_insider) {
            $comment_sql .= " AND isprivate = 0 ";
        }
        $comment_sql .= "
            ORDER BY bug_when DESC
               LIMIT 1
        ";

        my $attach_sql = "
            SELECT description, isprivate
              FROM attachments
             WHERE attach_id = ?
        ";

        # work on an initial list of bugs

        my $list = $dbh->selectall_arrayref($bugs_sql, undef, $product->id);
        my @bugs;

        foreach my $entry (@$list) {
            my ($bug_id, $summary, $reporter_id, $creation_ts) = @$entry;

            next unless $user->can_see_bug($bug_id);

            # get last comment information

            my ($comment_count) = $dbh->selectrow_array($comment_count_sql, undef, $bug_id);
            my ($commenter_id, $comment_ts, $type, $comment, $extra)
                = $dbh->selectrow_array($comment_sql, undef, $bug_id);
            my $commenter = 0;

            # apply selected filters

            if ($filter_commenter) {
                next if $comment_count <= 1;

                if ($filter_commenter_on eq 'reporter') {
                    next if $commenter_id != $reporter_id;

                } elsif ($filter_commenter_on eq 'noconfirm') {
                    $commenter = Bugzilla::User->new($commenter_id);
                    next if $commenter_id != $reporter_id
                        || $commenter->in_group('canconfirm');

                } elsif ($filter_commenter_on eq 'is') {
                    next if $commenter_id != $filter_commenter_id;
                }
            } else {
                $input->{'commenter'} = '';
                $input->{'commenter_is'} = '';
            }

            if ($filter_last) {
                my $comment_time = str2time($comment_ts)
                    or next;
                if ($filter_last_period == -1) {
                    next if $comment_time >= $filter_last_time;
                } else {
                    next if $now - $comment_time <= 60 * 60 * 24 * $filter_last_period;
                }
            } else {
                $input->{'last'} = '';
                $input->{'last_is'} = '';
            }

            # get data for attachment comments

            if ($comment eq '' && $type == CMT_ATTACHMENT_CREATED) {
                my ($description, $is_private) = $dbh->selectrow_array($attach_sql, undef, $extra);
                next if $is_private && !Bugzilla->user->is_insider;
                $comment = "(Attachment) " . $description;
            }

            # truncate long comments

            if (length($comment) > 80) {
                $comment = substr($comment, 0, 80) . '...';
            }

            # build bug hash for template

            my $bug = {};
            $bug->{id}            = $bug_id;
            $bug->{summary}       = $summary;
            $bug->{reporter}      = Bugzilla::User->new($reporter_id);
            $bug->{creation_ts}   = $creation_ts;
            $bug->{commenter}     = $commenter || Bugzilla::User->new($commenter_id);
            $bug->{comment_ts}    = $comment_ts;
            $bug->{comment}       = $comment;
            $bug->{comment_count} = $comment_count;
            push @bugs, $bug;
        }

        @bugs = sort { $b->{comment_ts} cmp $a->{comment_ts} } @bugs;

        $vars->{bugs} = \@bugs;
    } else {
        $input->{action} = '';
    }

    if (!$input->{filter_commenter} && !$input->{filter_last}) {
        $input->{filter_commenter} = 1;
    }
    
    $vars->{'input'} = $input;
}

1;
