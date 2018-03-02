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

use Bugzilla::Extension::PhabBugz::Project;
use Bugzilla::Extension::PhabBugz::Util qw(
    get_phab_bmo_ids
);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($phab_uri, $phab_sync_groups);

if (!Bugzilla->params->{phabricator_enabled}) {
    exit;
}

# Sanity checks
unless ($phab_uri = Bugzilla->params->{phabricator_base_uri}) {
    ThrowUserError('invalid_phabricator_uri');
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
    # Create group project if one does not yet exist
    my $phab_project_name = 'bmo-' . $group->name;
    my $project = Bugzilla::Extension::PhabBugz::Project->new_from_query({
        name => $phab_project_name
    });
    if (!$project) {
        my $secure_revision = Bugzilla::Extension::PhabBugz::Project->new_from_query({
            name => 'secure-revision'
        });
        $project = Bugzilla::Extension::PhabBugz::Project->create({
            name        => $phab_project_name,
            description => 'BMO Security Group for ' . $group->name,
            view_policy => $secure_revision->phid,
            edit_policy => $secure_revision->phid,
            join_policy => $secure_revision->phid
        });
    }

    if (my @group_members = get_group_members($group)) {
        $project->set_members(\@group_members);
        $project->update();
    }
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

    # Look up the phab ids for these users
    my $phab_users = get_phab_bmo_ids({ ids => [ keys %users ] });
    foreach my $phab_user (@{ $phab_users }) {
        $users{$phab_user->{id}}->{phab_phid} = $phab_user->{phid};
    }

    # We only need users who have accounts in phabricator
    return grep { $_->phab_phid } values %users;
}