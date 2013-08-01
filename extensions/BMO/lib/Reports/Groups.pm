# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::Groups;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::Util qw(trim);

sub admins_report {
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
        grep { !/^(?:bz_.+|canconfirm|editbugs|editbugs-team|everyone)$/ }
        map { lc($_->name) }
        Bugzilla::Group->get_all;
    unshift(@group_names, '');
    $vars->{'groups'} = \@group_names;

    # load selected group
    my $group = lc(trim($cgi->param('group') || ''));
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

1;
