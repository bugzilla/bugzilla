# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

######################################
# Test for xmlrpc call to User.get() #
######################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use QA::Util;
use QA::Tests qw(PRIVATE_BUG_USER);
use Test::More tests => 330;
our ($config, @clients) = get_rpc_clients();

my $get_user = $config->{'unprivileged_user_login'};
my $canconfirm_user = $config->{'canconfirm_user_login'};
my $priv_user = $config->{PRIVATE_BUG_USER . '_user_login'};
my $disabled = $config->{'disabled_user_login'};
my $disabled_match = substr($disabled, 0, length($disabled) - 1);

# These are the basic tests. There are tests for include_fields
# and exclude_field below.

my @tests = (
    { args => { names => [$get_user] },
      test => "Logged-out user can get unprivileged user by name"
    },
    { args  => { match => [$get_user] },
      test  => 'Logged-out user cannot use the match argument',
      error => 'Logged-out users cannot use',
    },
    { args  => { ids => [1] },
      test  => 'Logged-out users cannot use the "ids" argument',
      error => 'Logged-out users cannot use',
    },

    # match & names
    { user => 'unprivileged',
      args => { names => [$get_user] },
      test => "Unprivileged user can get himself",
    },
    { user => 'unprivileged',
      args => { match => [$get_user] },
      test => 'Logged-in user can use the match argument',
    },
    { user => 'unprivileged',
      args => { match => [$get_user], names => [$get_user] },
      test => 'Specifying the same thing in "match" and "names"',
    },

    # include_disabled
    { user => 'unprivileged',
      args => { match => [$get_user, $disabled_match] },
      test => 'Disabled users are not normally returned'
    },
    { user => 'unprivileged',
      args => { match => [$disabled_match], include_disabled => 1 },
      test => 'Specifying include_disabled returns disabled users'
    },
    { user => 'unprivileged',
      args => { match => [$disabled] },
      test => 'Full match on a disabled user returns that user',
    },

    # groups and group_ids
    { args  => { groups => ['QA-Selenium-TEST'] },
      test  => 'Specifying just groups fails',
      error => 'one of the following parameters',
    },
    { args => { group_ids => [1] },
      test => 'Specifying just group ids fails',
      error => 'one of the following parameters',
    },
    { args => { names => [$get_user, $priv_user], groups => ['QA-Selenium-TEST'] },
      test => 'Limiting the return value to a group while being logged out fails',
      error => 'The group you specified, QA-Selenium-TEST, is not valid here',
    },
    { user => 'unprivileged',
      args => { names => [$get_user, $priv_user], groups => ['missing_group'] },
      test => 'Limiting the return value to a group which does not exist fails',
      error => 'The group you specified, missing_group, is not valid here',
    },
    { user => 'unprivileged',
      args => { names => [$get_user, $priv_user], groups => ['QA-Selenium-TEST'] },
      test => 'Limiting the return value to a group you do not belong to fails',
      error => 'The group you specified, QA-Selenium-TEST, is not valid here',
    },
    { user => 'editbugs',
      args => { names => [$get_user, $priv_user], groups => ['Master', 'editbugs'] },
      test => 'Limiting the return value to some groups you do not belong to fails',
      error => 'The group you specified, Master, is not valid here',
    },
    { user => 'admin',
      args => { names => [$canconfirm_user], groups => ['canconfirm', 'editbugs'] },
      test => 'Limiting the return value to groups you belong to',
    },

    # groups returned
    { user => 'admin',
      args => { names => [$get_user] },
      test => 'Admin can get user',
    },
    { user => 'admin',
      args => { names => [$canconfirm_user] },
      test => 'Admin can get user',
    },
    { user => 'canconfirm',
      args => { names => [$canconfirm_user] },
      test => 'Privileged user can get himself',
    },
    { user => 'editbugs',
      args => { names => [$canconfirm_user] },
      test => 'Privileged user can get another user',
    },
);

sub post_success {
    my ($call, $t) = @_;

    my $result = $call->result;
    is(scalar @{ $result->{users} }, 1, "Got exactly one user");
    my $item = $result->{users}->[0];
    my $user = $t->{user} || '';

    if ($user eq 'admin') {
        ok(exists $item->{email} && exists $item->{can_login}
           && exists $item->{email_enabled} && exists $item->{login_denied_text},
           'Admin correctly gets all user fields');
    }
    elsif ($user) {
        ok(exists $item->{email} && exists $item->{can_login},
           'Logged-in user correctly gets email and can_login');
        ok(!exists $item->{email_enabled}
           && !exists $item->{login_denied_text},
           "Non-admin user doesn't get email_enabled and login_denied_text");
    }
    else {
        my @item_keys = sort keys %$item;
        is_deeply(\@item_keys, ['id', 'name', 'real_name'],
            'Only id, name, and real_name are returned to logged-out users');
        return;
    }

    my $username = $config->{"${user}_user_login"};
    # FIXME: We have no way to create a saved search or a saved report from
    #        the WebService, so we cannot test that the correct data is returned
    #        if the user is accessing his own account.
    if ($username eq $item->{name}) {
        ok(exists $item->{saved_searches},
           'Users can get the list of saved searches and reports for their own account');
    }
    else {
        ok(!exists $item->{saved_searches},
           "Users cannot get the list of saved searches and reports from someone else's acccount");
    }

    my @groups = map { $_->{name} } @{$item->{groups}};
    # Admins can see all groups a user belongs to (assuming they inherited
    # membership for all groups). Same for a user querying his own account.
    if ($username eq $item->{name} || $user eq 'admin') {
        if ($username eq $get_user) {
            ok(!scalar @groups, "The unprivileged user doesn't belong to any group");
        }
        elsif ($username eq $canconfirm_user) {
            ok(grep($_ eq 'canconfirm', @groups), "Group 'canconfirm' returned");
        }
    }
    else {
        ok(!scalar @groups, "No groups are visible to users without bless privs");
    }
}

foreach my $rpc (@clients) {
    $rpc->bz_run_tests(tests => \@tests, method => 'User.get',
                       post_success => \&post_success);

    #############################
    # Include and Exclude Tests #
    #############################

    my $include_nothing = $rpc->bz_call_success('User.get', {
        names => [$get_user], include_fields => ['asdfasdfsdf'],
    }, 'User.get including only invalid fields');
    is(scalar keys %{ $include_nothing->result->{users}->[0] }, 0,
       'No fields returned for user');

    my $include_one = $rpc->bz_call_success('User.get', {
        names => [$get_user], include_fields => ['id'],
    }, 'User.get including only id');
    is(scalar keys %{ $include_one->result->{users}->[0] }, 1,
       'Only one field returned for user');

    my $exclude_none = $rpc->bz_call_success('User.get', {
        names => [$get_user], exclude_fields => ['asdfasdfsdf'],
    }, 'User.get excluding only invalid fields');
    is(scalar keys %{ $exclude_none->result->{users}->[0] }, 3,
       'All fields returned for user');

    my $exclude_one = $rpc->bz_call_success('User.get', {
        names => [$get_user], exclude_fields => ['id'],
    }, 'User.get excluding id');
    is(scalar keys %{ $exclude_one->result->{users}->[0] }, 2,
       'Only two fields returned for user');

    my $override = $rpc->bz_call_success('User.get', {
        names => [$get_user], include_fields => ['id', 'name'],
        exclude_fields => ['id']
    }, 'User.get with both include and exclude');
    is(scalar keys %{ $override->result->{users}->[0] }, 1,
       'Only one field returned');
    ok(exists $override->result->{users}->[0]->{name},
       '...and that field is the "name" field');
}
