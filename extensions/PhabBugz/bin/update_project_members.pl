#!/usr/bin/perl

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
BEGIN { Bugzilla->extensions() }

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;

use Bugzilla::Extension::PhabBugz::Util qw(
    create_project
    get_members_by_bmo_id
    get_project_phid
    set_project_members
);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($phab_uri, $phab_api_key, $phab_sync_groups);

if (!Bugzilla->params->{phabricator_enabled}) {
    exit;
}

# Sanity checks
unless ($phab_uri = Bugzilla->params->{phabricator_base_uri}) {
    ThrowUserError('invalid_phabricator_uri');
}

unless ($phab_api_key = Bugzilla->params->{phabricator_api_key}) {
    ThrowUserError('invalid_phabricator_api_key');
}

unless ($phab_sync_groups = Bugzilla->params->{phabricator_sync_groups}) {
    ThrowUserError('invalid_phabricator_sync_groups');
}

# Loop through each group and perform the following:
#
# 1. Load flattened list of group members
# 2. Check to see if Phab project exists for 'bmo-<group_name>'
# 3. Create if does not exist with locked down policy.
# 4. Set project members to exact list
# 5. Profit

my $sync_groups = Bugzilla::Group->match({ name => [ split('[,\s]+', $phab_sync_groups) ] });

foreach my $group (@$sync_groups) {
    my @users = get_group_members($group);

    # Create group project if one does not yet exist
    my $phab_project_name = 'bmo-' . $group->name;
    my $project_phid = get_project_phid($phab_project_name);
    if (!$project_phid) {
        $project_phid = create_project($phab_project_name, 'BMO Security Group for ' . $group->name);
    }

    # Get the internal user ids for the bugzilla group members
    my $phab_user_ids = [];
    if (@users) {
        $phab_user_ids = get_members_by_bmo_id(\@users);
    }

    # Set the project members to the exact list
    set_project_members($project_phid, $phab_user_ids);
}

sub get_group_members {
    my ($group) = @_;
    my $group_obj = ref $group ? $group : Bugzilla::Group->check({ name => $group });
    my $members_all = $group_obj->members_complete();
    my %users;
    foreach my $name (keys %$members_all) {
        foreach my $user (@{ $members_all->{$name} }) {
            $users{$user->id} = $user;
        }
    }
    return values %users;
}
