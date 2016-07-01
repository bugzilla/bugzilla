# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::Groups;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::Util qw(trim datetime_from);
use JSON qw(encode_json);

sub admins_report {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    ($user->in_group('editbugs'))
        || ThrowUserError('auth_failure', { group  => 'editbugs',
                                            action => 'run',
                                            object => 'group_admins' });

    my @grouplist =
                  ($user->in_group('editusers') || $user->in_group('infrasec'))
                  ? map { lc($_->name) } Bugzilla::Group->get_all
                  : _get_permitted_membership_groups();

    my $groups = join(',', map { $dbh->quote($_) } @grouplist);

    my $query = "
        SELECT groups.id, " .
               $dbh->sql_group_concat('profiles.userid', "','", 1) . "
          FROM groups
               LEFT JOIN user_group_map
                    ON user_group_map.group_id = groups.id
                    AND user_group_map.isbless = 1
                    AND user_group_map.grant_type = 0
               LEFT JOIN profiles
                    ON user_group_map.user_id = profiles.userid
         WHERE groups.isbuggroup = 1
               AND groups.name IN ($groups)
      GROUP BY groups.name";

    my @groups;
    foreach my $row (@{ $dbh->selectall_arrayref($query) }) {
        my $group = Bugzilla::Group->new({ id => shift @$row, cache => 1});
        my @admins;
        if (my $admin_ids = shift @$row) {
            foreach my $uid (split(/,/, $admin_ids)) {
                push(@admins, Bugzilla::User->new({ id => $uid, cache => 1 }));
            }
        }
        push(@groups, { name        => $group->name,
                        description => $group->description,
                        owner       => $group->owner,
                        admins      => \@admins });
    }

    $vars->{'groups'} = \@groups;
}

sub membership_report {
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

sub members_report {
    my ($page, $vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;
    my $cgi = Bugzilla->cgi;

    ($user->in_group('editbugs'))
        || ThrowUserError('auth_failure', { group  => 'editbugs',
                                            action => 'run',
                                            object => 'group_admins' });

    my $privileged = $user->in_group('editusers') || $user->in_group('infrasec');
    $vars->{privileged} = $privileged;

    my @grouplist = $privileged
        ? map { lc($_->name) } Bugzilla::Group->get_all
        : _get_permitted_membership_groups();

    my $include_disabled = $cgi->param('include_disabled') ? 1 : 0;
    $vars->{'include_disabled'} = $include_disabled;

    # don't allow all groups, to avoid putting pain on the servers
    my @group_names =
        sort
        grep { !/^(?:bz_.+|canconfirm|editbugs|editbugs-team|everyone)$/ }
        @grouplist;
    unshift(@group_names, '');
    $vars->{'groups'} = \@group_names;

    # load selected group
    my $group = lc(trim($cgi->param('group') || ''));
    $group = '' unless grep { $_ eq $group } @group_names;
    return if $group eq '';
    my $group_obj = Bugzilla::Group->new({ name => $group });
    $vars->{'group'} = $group_obj;

    $vars->{'privileged'} = 1 if ($group_obj->owner && $group_obj->owner->id == $user->id);

    my @types;
    my $members = $group_obj->members_complete();
    foreach my $name (sort keys %$members) {
        push @types, {
            name    => ($name eq '_direct' ? 'direct' : $name),
            members => _filter_userlist($members->{$name}),
        }
    }

    # make it easy for the template to detect an empty group
    my $has_members = 0;
    foreach my $type (@types) {
        $has_members += scalar(@{ $type->{members} });
        last if $has_members;
    }
    @types = () unless $has_members;

    if ($page eq 'group_members.json') {
        my %users;
        foreach my $rh (@types) {
            foreach my $member (@{ $rh->{members} }) {
                my $login = $member->login;
                if (exists $users{$login}) {
                    push @{ $users{$login}->{groups} }, $rh->{name} if $privileged;
                }
                else {
                    my $rh_user = {
                        login      => $login,
                        membership => $rh->{name} eq 'direct' ? 'direct' : 'indirect',
                        rh_name => $rh->{name},
                    };
                    if ($privileged) {
                        $rh_user->{group}        = $rh->{name};
                        $rh_user->{groups}       = [ $rh->{name} ];
                        $rh_user->{lastseeon}    = $member->last_seen_date;
                        $rh_user->{mfa}          = $member->mfa;
                        $rh_user->{api_key_only} = $member->settings->{api_key_only}->{value} eq 'on'
                                                   ? JSON::true : JSON::false;
                    }
                    $users{$login} = $rh_user;
                }
            }
        }
        $vars->{types_json} = JSON->new->pretty->canonical->utf8->encode([ values %users ]);
    }
    else {
        my %users;
        foreach my $rh (@types) {
            foreach my $member (@{ $rh->{members} }) {
                $users{$member->login} = 1 unless exists $users{$member->login};
            }
        }
        $vars->{types} = \@types;
        $vars->{count} = scalar(keys %users);
    }
}

sub _filter_userlist {
    my ($list, $include_disabled) = @_;
    $list = [ grep { $_->is_enabled } @$list ] unless $include_disabled;
    my $now = DateTime->now();
    my $never = DateTime->from_epoch( epoch => 0 );
    foreach my $user (@$list) {
        my $last_seen = $user->last_seen_date ? datetime_from($user->last_seen_date) : $never;
        $user->{last_seen_days} = sprintf(
            '%.0f',
            $now->subtract_datetime_absolute($last_seen)->delta_seconds / (28 * 60 * 60));
    }
    return [ sort { lc($a->identity) cmp lc($b->identity) } @$list ];
}

# Groups that any user with editbugs can see the membership or admin lists for.
# Transparency FTW.
sub _get_permitted_membership_groups {
    my $user = Bugzilla->user;

    # Default publicly viewable groups
    my %default_public_groups = map { $_ => 1 } qw(
        bugzilla-approvers
        bugzilla-reviewers
        can_restrict_comments
        community-it-team
        mozilla-employee-confidential
        mozilla-foundation-confidential
        mozilla-reps
        qa-approvers
    );

    # We add the group to the permitted list if:
    # 1. it is a drivers group - this gives us a little
    #    future-proofing
    # 2. it is a one of the default public groups
    # 3. the user is the group's owner
    # 4. or the user can bless others into the group
    my @permitted_groups;
    foreach my $group (Bugzilla::Group->get_all) {
        my $name = $group->name;
        if ($name =~ /-drivers$/
            || exists $default_public_groups{$name}
            || ($group->owner && $group->owner->id == $user->id)
            || $user->can_bless($group->id))
        {
            push(@permitted_groups, $name);
        }
    }

    return @permitted_groups;
}

1;
