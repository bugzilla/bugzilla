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

use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib", "$FindBin::Bin/../local/lib/perl5";

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Group;
use Bugzilla::Util qw(diff_arrays);
use List::MoreUtils qw(any uniq);
BEGIN { Bugzilla->extensions }

{
    my $dbh = Bugzilla->dbh;
    my %IGNORE = map { $_ => 1 } qw(everyone);
    my @WATCH  = qw(mozilla-employee-confidential);
    my @REMOVE = qw(legal);
    my $JOB_NAME = "nightly-legal-bugs";

    my ($last_run) = $dbh->selectrow_array('select last_run from job_last_run where name = ?', undef, $JOB_NAME);
    my $and_at_time = $last_run ? ' AND at_time > ?' : '';
    my $and_profiles_when  = $last_run ? ' AND profiles_when > ?' : '';
    my @history_sql_params;
    if ($last_run) {
        @history_sql_params = ($last_run, get_field_id('bug_group'), $last_run);
    }
    else {
        @history_sql_params = (get_field_id('bug_group'));
    }

    my $history_sql = qq{
        SELECT
            'rename' AS type, object_id AS user_id, at_time AS time, removed as oldvalue, added as newvalue
        FROM
            audit_log
        WHERE
            class = 'Bugzilla::User' AND field = 'login_name' $and_at_time
        UNION ALL SELECT
            'editgroup', userid, profiles_when, oldvalue, newvalue
        FROM
            profiles_activity
        WHERE
            fieldid = ? $and_profiles_when
        ORDER BY time
    };

    my $group_group_sql =  q{
        SELECT
            member.name AS member, grantor.name AS name
        FROM
            group_group_map
                JOIN
            groups AS member ON member_id = member.id
                JOIN
            groups AS grantor ON grantor_id = grantor.id
        WHERE
            grant_type = 0
    };

    $dbh->bz_start_transaction();
    my ($timestamp) = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    # representing what we currently know about the users.
    my $group_sql         = 'SELECT userregexp, name FROM groups';
    my @user_regexp_rules = grep { $_->[0] } @{$dbh->selectall_arrayref($group_sql)};

    my %group_map;
    foreach my $pair (@{$dbh->selectall_arrayref($group_group_sql)}) {
        $group_map{$pair->[0]}{$pair->[1]} = 1;
    }

    my $history_items = $dbh->selectall_arrayref($history_sql, { Slice => {} }, @history_sql_params);
    my %is_removed_from;
    my %added_by_rename;
    foreach my $history_item (@$history_items) {
        my ($user_id, @removes, @adds);
        $user_id = $history_item->{user_id};

        if ($history_item->{type} eq 'rename') {
            my @oldvalue = grep { !$IGNORE{$_} } all_groups_for_login(\%group_map, \@user_regexp_rules, $history_item->{oldvalue});
            my @newvalue = grep { !$IGNORE{$_} } all_groups_for_login(\%group_map, \@user_regexp_rules, $history_item->{newvalue});
            my ($removed, $added) = diff_arrays(\@oldvalue, \@newvalue);
            @removes = @$removed;
            @adds = @$added;
            $added_by_rename{$user_id}{$_} = 1 for @adds;
            delete $added_by_rename{$user_id}{$_} for @removes;
        }
        else {
            @adds    = grep { !$IGNORE{$_} } all_groups_for_groups(\%group_map, [split(/\s*,\s/, $history_item->{newvalue})]);
            @removes = grep { !$IGNORE{$_} && !$added_by_rename{$user_id}{$_} } all_groups_for_groups(\%group_map, [split(/\s*,\s/, $history_item->{oldvalue})]);
        }
        $is_removed_from{$user_id}{$_} = 1 for @removes;
        delete $is_removed_from{$user_id}{$_} for @adds;
    }

    foreach my $user_id (keys %is_removed_from) {
        delete $is_removed_from{$user_id} if !any { $is_removed_from{$user_id}{$_} } @WATCH;
    }

    # the following user ids have left the group(s) we watch.
    my @user_ids = keys %is_removed_from;

    # Load nobody user and set as current
    my $auto_user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
    my $nobody    = Bugzilla::User->check({ name => 'nobody@mozilla.org' });
    Bugzilla->set_user($auto_user);

    my $sth_remove_mapping = $dbh->prepare('DELETE FROM user_group_map WHERE user_id = ? AND group_id = ? AND grant_type = ?');
    my @remove_groups     = map { Bugzilla::Group->check({name => $_}) } @REMOVE;
    my @remove_groups_all = map { Bugzilla::Group->check({name => $_}) } all_groups_for_groups(\%group_map, \@REMOVE);

    foreach my $user_id (@user_ids) {
        my $user = Bugzilla::User->check({id => $user_id});
        my @groups_removed_from;
        say 'Working on ', $user->identity;

        foreach my $remove_group (@remove_groups) {
            if ($user->in_group($remove_group)) {
                push @groups_removed_from, $remove_group->name;
                $sth_remove_mapping->execute($user_id, $remove_group->id, GRANT_DIRECT);
            }
        }

        if (@groups_removed_from) {
            $dbh->do('INSERT INTO profiles_activity'
                     . ' (userid, who, profiles_when, fieldid, oldvalue, newvalue)'
                     . ' VALUES (?, ?, now(), ?, ?, ?)',
                     undef,
                     $user_id, $auto_user->id,
                     get_field_id('bug_group'),
                     join(', ', @groups_removed_from), '');
            Bugzilla->memcached->clear_config({ key => "user_groups.$user_id" });
        }
        $user->force_bug_dissociation($nobody, \@remove_groups_all, $timestamp);
    }

    my $insert_or_update = q{ INSERT INTO job_last_run (name, last_run) VALUES (?, ?)
                              ON DUPLICATE KEY UPDATE last_run = ? };
    $dbh->do($insert_or_update, undef, $JOB_NAME, $timestamp, $timestamp);
    $dbh->bz_commit_transaction();
}

sub all_groups_for_login {
    my ($map, $rules, $login) = @_;
    return uniq sort map { groups($map, $_) } user_regexp_groups($rules, $login);
}

sub user_regexp_groups {
    my ($rules, $login) = @_;
    return map { $_->[1] } grep { $login =~ $_->[0] } @$rules;
}

sub all_groups_for_groups {
    my ($map, $groups) = @_;
    return uniq sort map { groups($map, $_) } @$groups;
}

sub groups {
    my ($map, $group) = @_;
    return $group, map { $_, groups($map, $_) } keys %{$map->{$group}};
}
