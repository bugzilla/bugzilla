# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports;
use strict;

use Bugzilla::Extension::BMO::Data qw($cf_disabled_flags);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::Util qw(trim detaint_natural trick_taint correct_urlbase);

use Date::Parse;
use DateTime;
use JSON qw(-convert_blessed_universally);
use List::MoreUtils qw(uniq);

use base qw(Exporter);

our @EXPORT_OK = qw(user_activity_report
                    triage_reports
                    group_admins_report
                    email_queue_report
                    release_tracking_report
                    group_membership_report
                    group_members_report);

sub user_activity_report {
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
        my $dt = DateTime->now()->subtract('weeks' => 8);
        $from = $dt->ymd('-');
    }
    if ($to eq '') {
        my $dt = DateTime->now();
        $to = $dt->ymd('-');
    }

    if ($action eq 'run') {
        if ($input->{'who'} eq '') {
            ThrowUserError('user_activity_missing_username');
        }
        Bugzilla::User::match_field({ 'who' => {'type' => 'multi'} });

        my $from_dt = _string_to_datetime($from);
        $from = $from_dt->ymd();

        my $to_dt = _string_to_datetime($to);
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

sub _string_to_datetime {
    my $input = shift;
    my $time = _parse_date($input)
        or ThrowUserError('report_invalid_date', { date => $input });
    return _time_to_datetime($time);
}

sub _time_to_datetime {
    my $time = shift;
    return DateTime->from_epoch(epoch => $time)
                   ->set_time_zone('local')
                   ->truncate(to => 'day');
}

sub _parse_date {
    my ($str) = @_;
    if ($str =~ /^(-|\+)?(\d+)([hHdDwWmMyY])$/) {
        # relative date
        my ($sign, $amount, $unit, $date) = ($1, $2, lc $3, time);
        my ($sec, $min, $hour, $mday, $month, $year, $wday)  = localtime($date);
        $amount = -$amount if $sign && $sign eq '+';
        if ($unit eq 'w') {
            # convert weeks to days
            $amount = 7*$amount + $wday;
            $unit = 'd';
        }
        if ($unit eq 'd') {
            $date -= $sec + 60*$min + 3600*$hour + 24*3600*$amount;
            return $date;
        }
        elsif ($unit eq 'y') {
            return str2time(sprintf("%4d-01-01 00:00:00", $year+1900-$amount));
        }
        elsif ($unit eq 'm') {
            $month -= $amount;
            while ($month<0) { $year--; $month += 12; }
            return str2time(sprintf("%4d-%02d-01 00:00:00", $year+1900, $month+1));
        }
        elsif ($unit eq 'h') {
            # Special case 0h for 'beginning of this hour'
            if ($amount == 0) {
                $date -= $sec + 60*$min;
            } else {
                $date -= 3600*$amount;
            }
            return $date;
        }
        return undef;
    }
    return str2time($str);
}

sub triage_reports {
    my ($vars, $filter) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $user = Bugzilla->user;

    if (exists $input->{'action'} && $input->{'action'} eq 'run' && $input->{'product'}) {

        # load product and components from input

        my $product = Bugzilla::Product->new({ name => $input->{'product'} })
            || ThrowUserError('invalid_object', { object => 'Product', value => $input->{'product'} });

        my @component_ids;
        if ($input->{'component'} ne '') {
            my $ra_components = ref($input->{'component'})
                ? $input->{'component'} : [ $input->{'component'} ];
            foreach my $component_name (@$ra_components) {
                my $component = Bugzilla::Component->new({ name => $component_name, product => $product })
                    || ThrowUserError('invalid_object', { object => 'Component', value => $component_name });
                push @component_ids, $component->id;
            }
        }

        # determine which comment filters to run

        my $filter_commenter = $input->{'filter_commenter'};
        my $filter_commenter_on = $input->{'commenter'};
        my $filter_last = $input->{'filter_last'};
        my $filter_last_period = $input->{'last'};

        if (!$filter_commenter || $filter_last) {
            $filter_commenter = '1';
            $filter_commenter_on = 'reporter';
        }

        my $filter_commenter_id;
        if ($filter_commenter && $filter_commenter_on eq 'is') {
            Bugzilla::User::match_field({ 'commenter_is' => {'type' => 'single'} });
            my $user = Bugzilla::User->new({ name => $input->{'commenter_is'} })
                || ThrowUserError('invalid_object', { object => 'User', value => $input->{'commenter_is'} });
            $filter_commenter_id = $user ? $user->id : 0;
        }

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

        # form sql queries

        my $now = (time);
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

sub group_admins_report {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    ($user->in_group('editusers') || $user->in_group('infrasec'))
        || ThrowUserError('auth_failure', { group  => 'editusers',
                                            action => 'run',
                                            object => 'group_admins' });

    my $query = "
        SELECT groups.name, " .
               $dbh->sql_group_concat('profiles.login_name', "','", 1) . "
          FROM groups
               LEFT JOIN user_group_map
                    ON user_group_map.group_id = groups.id
                    AND user_group_map.isbless = 1
                    AND user_group_map.grant_type = 0
               LEFT JOIN profiles
                    ON user_group_map.user_id = profiles.userid
         WHERE groups.isbuggroup = 1
      GROUP BY groups.name";
    
    my @groups;
    foreach my $group (@{ $dbh->selectall_arrayref($query) }) {
        my @admins;
        if ($group->[1]) {
            foreach my $admin (split(/,/, $group->[1])) {
                push(@admins, Bugzilla::User->new({ name => $admin }));
            }
        }
        push(@groups, { name => $group->[0], admins => \@admins });
    }

    $vars->{'groups'} = \@groups;
}

sub group_membership_report {
    my ($page, $vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;
    my $cgi = Bugzilla->cgi;

    ($user->in_group('editusers') || $user->in_group('infrasec'))
        || ThrowUserError('auth_failure', { group  => 'editusers',
                                            action => 'run',
                                            object => 'group_admins' });

    my $who = $cgi->param('who');
    if (!defined($who) || $who eq '') {
        if ($page eq 'group_membership.txt') {
            print $cgi->redirect("page.cgi?id=group_membership.html&output=txt");
            exit;
        }
        $vars->{'output'} = $cgi->param('output');
        return;
    }

    Bugzilla::User::match_field({ 'who' => {'type' => 'multi'} });
    $who = Bugzilla->input_params->{'who'};
    $who = ref($who) ? $who : [ $who ];

    my @users;
    foreach my $login (@$who) {
        my $u = Bugzilla::User->new(login_to_id($login, 1));

        # this is lifted from $user->groups() 
        # we need to show which groups are direct and which are inherited

        my $groups_to_check = $dbh->selectcol_arrayref(
            q{SELECT DISTINCT group_id
                FROM user_group_map
               WHERE user_id = ? AND isbless = 0}, undef, $u->id);

        my $rows = $dbh->selectall_arrayref(
            "SELECT DISTINCT grantor_id, member_id
               FROM group_group_map
              WHERE grant_type = " . GROUP_MEMBERSHIP);

        my %group_membership;
        foreach my $row (@$rows) {
            my ($grantor_id, $member_id) = @$row;
            push (@{ $group_membership{$member_id} }, $grantor_id);
        }

        my %checked_groups;
        my %direct_groups;
        my %indirect_groups;
        my %groups;

        foreach my $member_id (@$groups_to_check) {
            $direct_groups{$member_id} = 1;
        }

        while (scalar(@$groups_to_check) > 0) {
            my $member_id = shift @$groups_to_check;
            if (!$checked_groups{$member_id}) {
                $checked_groups{$member_id} = 1;
                my $members = $group_membership{$member_id};
                my @new_to_check = grep(!$checked_groups{$_}, @$members);
                push(@$groups_to_check, @new_to_check);
                foreach my $id (@new_to_check) {
                    $indirect_groups{$id} = $member_id;
                }
                $groups{$member_id} = 1;
            }
        }

        my @groups;
        my $ra_groups = Bugzilla::Group->new_from_list([keys %groups]);
        foreach my $group (@$ra_groups) {
            my $via;
            if ($direct_groups{$group->id}) {
                $via = '';
            } else {
                foreach my $g (@$ra_groups) {
                    if ($g->id == $indirect_groups{$group->id}) {
                        $via = $g->name;
                        last;
                    }
                }
            }
            push @groups, {
                name => $group->name,
                desc => $group->description,
                via  => $via,
            };
        }

        push @users, {
            user   => $u,
            groups => \@groups,
        };
    }

    $vars->{'who'} = $who;
    $vars->{'users'} = \@users;
}

sub group_members_report {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;
    my $cgi = Bugzilla->cgi;

    ($user->in_group('editusers') || $user->in_group('infrasec'))
        || ThrowUserError('auth_failure', { group  => 'editusers',
                                            action => 'run',
                                            object => 'group_admins' });

    my $include_disabled = $cgi->param('include_disabled') ? 1 : 0;
    $vars->{'include_disabled'} = $include_disabled;

    # don't allow all groups, to avoid putting pain on the servers
    my @group_names =
        sort
        grep { !/^(?:bz_.+|canconfirm|editbugs|everyone)$/ }
        map { lc($_->name) }
        Bugzilla::Group->get_all;
    unshift(@group_names, '');
    $vars->{'groups'} = \@group_names;

    # load selected group
    my $group = lc(trim($cgi->param('group') // ''));
    $group = '' unless grep { $_ eq $group } @group_names;
    return if $group eq '';
    my $group_obj = Bugzilla::Group->new({ name => $group });
    $vars->{'group'} = $group;

    # direct members
    my @types = (
        {
            name    => 'direct',
            members => _filter_userlist($group_obj->members_direct, $include_disabled),
        },
    );

    # indirect members, by group
    foreach my $member_group (sort @{ $group_obj->grant_direct(GROUP_MEMBERSHIP) }) {
        push @types, {
            name    => $member_group->name,
            members => _filter_userlist($member_group->members_direct, $include_disabled),
        },
    }

    # make it easy for the template to detect an empty group
    my $has_members = 0;
    foreach my $type (@types) {
        $has_members += scalar(@{ $type->{members} });
        last if $has_members;
    }
    @types = () unless $has_members;

    if (@types) {
        # add last-login
        my $user_ids = join(',', map { map { $_->id } @{ $_->{members} } } @types);
        my $tokens = $dbh->selectall_hashref("
            SELECT profiles.userid,
                (SELECT DATEDIFF(curdate(), logincookies.lastused) lastseen
                   FROM logincookies
                  WHERE logincookies.userid = profiles.userid
                  ORDER BY lastused DESC
                  LIMIT 1) lastseen
            FROM profiles
            WHERE userid IN ($user_ids)",
            'userid');
        foreach my $type (@types) {
            foreach my $member (@{ $type->{members} }) {
                $member->{lastseen} = 
                    defined $tokens->{$member->id}->{lastseen}
                    ? $tokens->{$member->id}->{lastseen}
                    : '>' . MAX_LOGINCOOKIE_AGE;
            }
        }
    }

    $vars->{'types'} = \@types;
}

sub _filter_userlist {
    my ($list, $include_disabled) = @_;
    $list = [ grep { $_->is_enabled } @$list ] unless $include_disabled;
    return [ sort { lc($a->identity) cmp lc($b->identity) } @$list ];
}

sub email_queue_report {
    my ($vars, $filter) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    $user->in_group('admin') || $user->in_group('infra')
        || ThrowUserError('auth_failure', { group  => 'admin', 
                                            action => 'run', 
                                            object => 'email_queue' });

    my $query = "
        SELECT j.jobid,
               j.insert_time,
               j.run_after AS run_time,
               COUNT(e.jobid) AS error_count,
               MAX(e.error_time) AS error_time,
               e.message AS error_message
          FROM ts_job j
               LEFT JOIN ts_error e ON e.jobid = j.jobid
      GROUP BY j.jobid
      ORDER BY j.run_after";

    $vars->{'jobs'} = $dbh->selectall_arrayref($query, { Slice => {} });
    $vars->{'now'} = (time);
}

sub release_tracking_report {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $user = Bugzilla->user;

    my @flag_names = qw(
        approval-mozilla-release
        approval-mozilla-beta
        approval-mozilla-aurora
        approval-mozilla-central
        approval-comm-release
        approval-comm-beta
        approval-comm-aurora
        approval-calendar-release
        approval-calendar-beta
        approval-calendar-aurora
        approval-mozilla-esr10
    );

    my @flags_json;
    my @fields_json;
    my @products_json;

    #
    # tracking flags
    #

    my $all_products = $user->get_selectable_products;
    my @usable_products;

    # build list of flags and their matching products

    my @invalid_flag_names;
    foreach my $flag_name (@flag_names) {
        # grab all matching flag_types
        my @flag_types = @{Bugzilla::FlagType::match({ name => $flag_name, is_active => 1 })};

        # remove invalid flags
        if (!@flag_types) {
            push @invalid_flag_names, $flag_name;
            next;
        }

        # we need a list of products, based on inclusions/exclusions
        my @products;
        my %flag_types;
        foreach my $flag_type (@flag_types) {
            $flag_types{$flag_type->name} = $flag_type->id;
            my $has_all = 0;
            my @exclusion_ids;
            my @inclusion_ids;
            foreach my $flag_type (@flag_types) {
                if (scalar keys %{$flag_type->inclusions}) {
                    my $inclusions = $flag_type->inclusions;
                    foreach my $key (keys %$inclusions) {
                        push @inclusion_ids, ($inclusions->{$key} =~ /^(\d+)/);
                    }
                } elsif (scalar keys %{$flag_type->exclusions}) {
                    my $exclusions = $flag_type->exclusions;
                    foreach my $key (keys %$exclusions) {
                        push @exclusion_ids, ($exclusions->{$key} =~ /^(\d+)/);
                    }
                } else {
                    $has_all = 1;
                    last;
                }
            }

            if ($has_all) {
                push @products, @$all_products;
            } elsif (scalar @exclusion_ids) {
                push @products, @$all_products;
                foreach my $exclude_id (uniq @exclusion_ids) {
                    @products = grep { $_->id != $exclude_id } @products;
                }
            } else {
                foreach my $include_id (uniq @inclusion_ids) {
                    push @products, grep { $_->id == $include_id } @$all_products;
                }
            }
        }
        @products = uniq @products;
        push @usable_products, @products;
        my @product_ids = map { $_->id } sort { lc($a->name) cmp lc($b->name) } @products;

        push @flags_json, {
            name => $flag_name,
            id => $flag_types{$flag_name} || 0,
            products => \@product_ids,
            fields => [],
        };
    }
    foreach my $flag_name (@invalid_flag_names) {
        @flag_names = grep { $_ ne $flag_name } @flag_names;
    }
    @usable_products = uniq @usable_products;

    # build a list of tracking flags for each product
    # also build the list of all fields

    my @unlink_products;
    foreach my $product (@usable_products) {
        my @fields =
            grep { _is_active_status_field($_->name) }
            Bugzilla->active_custom_fields({ product => $product });
        my @field_ids = map { $_->id } @fields;
        if (!scalar @fields) {
            push @unlink_products, $product;
            next;
        }

        # product
        push @products_json, {
            name => $product->name,
            id => $product->id,
            fields => \@field_ids,
        };

        # add fields to flags
        foreach my $rh (@flags_json) {
            if (grep { $_ eq $product->id } @{$rh->{products}}) {
                push @{$rh->{fields}}, @field_ids;
            }
        }

        # add fields to fields_json
        foreach my $field (@fields) {
            my $existing = 0;
            foreach my $rh (@fields_json) {
                if ($rh->{id} == $field->id) {
                    $existing = 1;
                    last;
                }
            }
            if (!$existing) {
                push @fields_json, {
                    name => $field->name,
                    id => $field->id,
                };
            }
        }
    }
    foreach my $rh (@flags_json) {
        my @fields = uniq @{$rh->{fields}};
        $rh->{fields} = \@fields;
    }

    # remove products which aren't linked with status fields

    foreach my $rh (@flags_json) {
        my @product_ids;
        foreach my $id (@{$rh->{products}}) {
            unless (grep { $_->id == $id } @unlink_products) {
                push @product_ids, $id;
            }
            $rh->{products} = \@product_ids;
        }
    }

    #
    # rapid release dates
    #

    my @ranges;
    my $start_date = _string_to_datetime('2011-08-16');
    my $end_date = $start_date->clone->add(weeks => 6)->add(days => -1);
    my $now_date = _string_to_datetime('2012-11-19');

    while ($start_date <= $now_date) {
        unshift @ranges, {
            value => sprintf("%s-%s", $start_date->ymd(''), $end_date->ymd('')),
            label => sprintf("%s and %s", $start_date->ymd('-'), $end_date->ymd('-')),
        };

        $start_date = $end_date->clone;;
        $start_date->add(days => 1);
        $end_date->add(weeks => 6);
    }

    # 2012-11-20 - 2013-01-06 was a 7 week release cycle instead of 6
    $start_date = _string_to_datetime('2012-11-20');
    $end_date = $start_date->clone->add(weeks => 7)->add(days => -1);
    unshift @ranges, {
        value => sprintf("%s-%s", $start_date->ymd(''), $end_date->ymd('')),
        label => sprintf("%s and %s", $start_date->ymd('-'), $end_date->ymd('-')),
    };

    # Back on track with 6 week releases
    $start_date = _string_to_datetime('2013-01-08');
    $end_date = $start_date->clone->add(weeks => 6)->add(days => -1);
    $now_date = _time_to_datetime((time));

    while ($start_date <= $now_date) {
        unshift @ranges, {
            value => sprintf("%s-%s", $start_date->ymd(''), $end_date->ymd('')),
            label => sprintf("%s and %s", $start_date->ymd('-'), $end_date->ymd('-')),
        };

        $start_date = $end_date->clone;;
        $start_date->add(days => 1);
        $end_date->add(weeks => 6);
    }

    push @ranges, {
        value => '*',
        label => 'Anytime',
    };

    #
    # run report
    #

    if ($input->{q} && !$input->{edit}) {
        my $q = _parse_query($input->{q});

        my @where;
        my @params;
        my $query = "
            SELECT DISTINCT b.bug_id
              FROM bugs b
                   INNER JOIN flags f ON f.bug_id = b.bug_id ";

        if ($q->{start_date}) {
            $query .= "INNER JOIN bugs_activity a ON a.bug_id = b.bug_id ";
        }

        $query .= "WHERE ";

        if ($q->{start_date}) {
            push @where, "(a.fieldid = ?)";
            push @params, $q->{field_id};

            push @where, "(a.bug_when >= ?)";
            push @params, $q->{start_date} . ' 00:00:00';
            push @where, "(a.bug_when < ?)";
            push @params, $q->{end_date} . ' 00:00:00';

            push @where, "(a.added LIKE ?)";
            push @params, '%' . $q->{flag_name} . $q->{flag_status} . '%';
        }

        push @where, "(f.type_id IN (SELECT id FROM flagtypes WHERE name = ?))";
        push @params, $q->{flag_name};

        push @where, "(f.status = ?)";
        push @params, $q->{flag_status};

        if ($q->{product_id}) {
            push @where, "(b.product_id = ?)";
            push @params, $q->{product_id};
        }

        if (scalar @{$q->{fields}}) {
            my @fields;
            foreach my $field (@{$q->{fields}}) {
                push @fields,
                    "(" .
                    ($field->{value} eq '+' ? '' : '!') .
                    "(b.".$field->{name}." IN ('fixed','verified'))" .
                    ") ";
            }
            my $join = uc $q->{join};
            push @where, '(' . join(" $join ", @fields) . ')';
        }

        $query .= join("\nAND ", @where);

        if ($input->{debug}) {
            print "Content-Type: text/plain\n\n";
            $query =~ s/\?/\000/g;
            foreach my $param (@params) {
                $query =~ s/\000/$param/;
            }
            print "$query\n";
            exit;
        }

        my $bugs = $dbh->selectcol_arrayref($query, undef, @params);
        push @$bugs, 0 unless @$bugs;

        my $urlbase = correct_urlbase();
        my $cgi = Bugzilla->cgi;
        print $cgi->redirect(
            -url => "${urlbase}buglist.cgi?bug_id=" . join(',', @$bugs)
        );
        exit;
    }

    #
    # set template vars
    #

    my $json = JSON->new();
    if (0) {
        # debugging
        $json->shrink(0);
        $json->canonical(1);
        $vars->{flags_json} = $json->pretty->encode(\@flags_json);
        $vars->{products_json} = $json->pretty->encode(\@products_json);
        $vars->{fields_json} = $json->pretty->encode(\@fields_json);
    } else {
        $json->shrink(1);
        $vars->{flags_json} = $json->encode(\@flags_json);
        $vars->{products_json} = $json->encode(\@products_json);
        $vars->{fields_json} = $json->encode(\@fields_json);
    }

    $vars->{flag_names} = \@flag_names;
    $vars->{ranges} = \@ranges;
    $vars->{default_query} = $input->{q};
    foreach my $field (qw(product flags range)) {
        $vars->{$field} = $input->{$field};
    }
}

sub _parse_query {
    my $q = shift;
    my @query = split(/:/, $q);
    my $query;

    # field_id for flag changes
    $query->{field_id} = get_field_id('flagtypes.name');

    # flag_name
    my $flag_name = shift @query;
    @{Bugzilla::FlagType::match({ name => $flag_name, is_active => 1 })}
        or ThrowUserError('report_invalid_parameter', { name => 'flag_name' });
    trick_taint($flag_name);
    $query->{flag_name} = $flag_name;

    # flag_status
    my $flag_status = shift @query;
    $flag_status =~ /^([\?\-\+])$/
        or ThrowUserError('report_invalid_parameter', { name => 'flag_status' });
    $query->{flag_status} = $1;

    # date_range -> from_ymd to_ymd
    my $date_range = shift @query;
    if ($date_range ne '*') {
        $date_range =~ /^(\d\d\d\d)(\d\d)(\d\d)-(\d\d\d\d)(\d\d)(\d\d)$/
            or ThrowUserError('report_invalid_parameter', { name => 'date_range' });
        $query->{start_date} = "$1-$2-$3";
        $query->{end_date} = "$4-$5-$6";
    }

    # product_id
    my $product_id = shift @query;
    $product_id =~ /^(\d+)$/
        or ThrowUserError('report_invalid_parameter', { name => 'product_id' });
    $query->{product_id} = $1;

    # join
    my $join = shift @query;
    $join =~ /^(and|or)$/
        or ThrowUserError('report_invalid_parameter', { name => 'join' });
    $query->{join} = $1;

    # fields
    my @fields;
    foreach my $field (@query) {
        $field =~ /^(\d+)([\-\+])$/
            or ThrowUserError('report_invalid_parameter', { name => 'fields' });
        my ($id, $value) = ($1, $2);
        my $field_obj = Bugzilla::Field->new($id)
            or ThrowUserError('report_invalid_parameter', { name => 'field_id' });
        push @fields, { id => $id, value => $value, name => $field_obj->name };
    }
    $query->{fields} = \@fields;

    return $query;
}

sub _is_active_status_field {
    my ($field_name) = @_;
    if ($field_name =~ /^cf_status/) {
        return !grep { $field_name eq $_ } @$cf_disabled_flags
    }
    return 0;
}

1;
