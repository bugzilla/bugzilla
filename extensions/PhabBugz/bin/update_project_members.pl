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

use LWP::UserAgent;
use JSON qw(encode_json decode_json);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($phab_uri, $phab_api_key, $phab_sync_groups, $ua);

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
    my $project_id = get_phab_project($phab_project_name);
    if (!$project_id) {
        $project_id = create_phab_project($phab_project_name, 'BMO Security Group for ' . $group->name);
    }

    # Get the internal user ids for the bugzilla group members
    my $phab_user_ids = get_phab_members_by_bmo_id(\@users);

    # Set the project members to the exact list
    set_phab_project_members($project_id, $phab_user_ids);
}

# Bugzilla

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

# Projects

sub get_phab_project {
    my ($project) = @_;

    my $data = {
        queryKey => 'active',
        constraints => {
            name => $project
        }
    };

    my $result = request('project.search', $data);
    if (!$result->{result}{data}) {
        return undef;
    }
    return $result->{result}{data}[0]{phid};
}

sub create_phab_project {
    my ($project, $description, $members) = @_;

    my $data = {
        transactions => [
            { type => 'name',  value => $project },
            { type => 'description', value => $description },
            { type => 'edit',  value => 'admin'},
            { type => 'join',  value => 'admin' },
            { type => 'icon',  value => 'group' },
            { type => 'color', value => 'red' }
        ]
    };

    my $result = request('project.edit', $data);
    return $result->{result}{object}{phid};
}

sub set_phab_project_members {
    my ($project_id, $phab_user_ids) = @_;

    my $data = {
        objectIdentifier => $project_id,
        transactions => [
            { type => 'members.set',  value => $phab_user_ids }
        ]
    };

    my $result = request('project.edit', $data);
    return $result->{result}{object}{phid};
}

# Members

sub get_phab_members_by_bmo_id {
    my ($users) = @_;

    my $data = {
        accountids => [ map { $_->id } @$users ]
    };

    my $result = request('bmoexternalaccount.search', $data);
    if (!$result->{result}) {
        return [];
    }

    my @phab_ids;
    foreach my $user (@{ $result->{result} }) {
        push(@phab_ids, $user->{phid});
    }
    return \@phab_ids;
}

# Utility

sub request {
    my ($method, $data) = @_;

    if (!$ua) {
        $ua = LWP::UserAgent->new(timeout => 10);
        if (Bugzilla->params->{proxy_url}) {
            $ua->proxy('https', Bugzilla->params->{proxy_url});
        }
        $ua->default_header('Content-Type' => 'application/x-www-form-urlencoded');
    }

    my $full_uri = $phab_uri . '/api/' . $method;

    $data->{__conduit__} = { token => $phab_api_key };

    my $response = $ua->post($full_uri, { params => encode_json($data) });

    $response->is_error
        && ThrowCodeError('phabricator_api_error',
                          { reason => $response->message });

    my $result = decode_json($response->content);
    if ($result->{error_code}) {
        ThrowCodeError('phabricator_api_error',
                       { code   => $result->{error_code},
                         reason => $result->{error_info} });
    }
    return $result;
}
