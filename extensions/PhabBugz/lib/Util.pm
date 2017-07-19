# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Util;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Error;

use Data::Dumper;
use JSON qw(encode_json decode_json);
use LWP::UserAgent;

use base qw(Exporter);

our @EXPORT = qw(
    create_revision_attachment
    create_private_revision_policy
    create_project
    edit_revision_policy
    get_bug_role_phids
    get_members_by_bmo_id
    get_project_phid
    get_revisions_by_ids
    intersect
    make_revision_public
    request
    set_project_members
);

sub get_revisions_by_ids {
    my ($ids) = @_;

    my $data = {
        queryKey => 'all',
        constraints => {
            ids => $ids
        }
    };

    my $result = request('differential.revision.search', $data);

    ThrowUserError('invalid_phabricator_revision_id')
        unless (exists $result->{result}{data} && @{ $result->{result}{data} });

    return @{$result->{result}{data}};
}

sub create_revision_attachment {
    my ($bug, $revision_id, $revision_title) = @_;

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction;

    my ($timestamp) = $dbh->selectrow_array("SELECT NOW()");

    my $attachment = Bugzilla::Attachment->create({
        bug           => $bug,
        creation_ts   => $timestamp,
        data          => 'http://phabricator.test/D' . $revision_id,
        description   => $revision_title,
        filename      => 'phabricator-D' . $revision_id . '-url.txt',
        ispatch       => 0,
        isprivate     => 0,
        mimetype      => 'text/x-phabricator-request',
    });

    $bug->update($timestamp);
    $attachment->update($timestamp);

    $dbh->bz_commit_transaction;

    return $attachment;
}

sub intersect {
    my ($list1, $list2) = @_;
    my %e = map { $_ => undef } @{$list1};
    return grep { exists( $e{$_} ) } @{$list2};
}

sub get_bug_role_phids {
    my ($bug) = @_;

    my @bug_users = ( $bug->reporter );
    push(@bug_users, $bug->assigned_to)
        if !$bug->assigned_to->email !~ /^nobody\@mozilla\.org$/;
    push(@bug_users, $bug->qa_contact) if $bug->qa_contact;
    push(@bug_users, @{ $bug->cc_users }) if @{ $bug->cc_users };

    return get_members_by_bmo_id(\@bug_users);
}

sub create_private_revision_policy {
    my ($bug, $groups) = @_;

    my $project_phids = [];
    foreach my $group (@$groups) {
        my $phid = get_project_phid('bmo-' . $group);
        push(@$project_phids, $phid) if $phid;
    }

    ThrowUserError('invalid_phabricator_sync_groups') unless @$project_phids;

    my $data = {
        objectType => 'DREV',
        default    => 'deny',
        policy     => [
            {
                action => 'allow',
                rule   => 'PhabricatorProjectsPolicyRule',
                value  => $project_phids,
            },
            {
                action => 'allow',
                rule   => 'PhabricatorSubscriptionsSubscribersPolicyRule',
            }
        ]
    };

    my $result = request('policy.create', $data);
    return $result->{result}{phid};
}

sub make_revision_public {
    my ($revision_phid) = @_;
    return request('differential.revision.edit', {
        transactions => [
            {
                type  => "view",
                value => "users"
            }
        ],
        objectIdentifier => $revision_phid
    });
}

sub edit_revision_policy {
    my ($revision_phid, $policy_phid, $subscribers) = @_;

    my $data = {
        transactions => [
            {
                type  => 'view',
                value => $policy_phid
            },
            {
                type  => 'edit',
                value => $policy_phid
            }
        ],
        objectIdentifier => $revision_phid
    };

    if (@$subscribers) {
        push(@{ $data->{transactions} }, {
            type  => 'subscribers.add',
            value => $subscribers
        });
    }

    return request('differential.revision.edit', $data);
}

sub get_project_phid {
    my $project = shift;

    my $data = {
        queryKey => 'all',
        constraints => {
            name => $project
        }
    };

    my $result = request('project.search', $data);
    return undef
        unless (exists $result->{result}{data} && @{ $result->{result}{data} });

    return $result->{result}{data}[0]{phid};
}

sub create_project {
    my ($project, $description, $members) = @_;

    my $data = {
        transactions => [
            { type => 'name',  value => $project           },
            { type => 'description', value => $description },
            { type => 'edit',  value => 'admin'            },
            { type => 'join',  value => 'admin'            },
            { type => 'view',  value => 'admin'            },
            { type => 'icon',  value => 'group'            },
            { type => 'color', value => 'red'              }
        ]
    };

    my $result = request('project.edit', $data);
    return $result->{result}{object}{phid};
}

sub set_project_members {
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

sub get_members_by_bmo_id {
    my $users = shift;

    my $data = {
        accountids => [ map { $_->id } @$users ]
    };

    my $result = request('bmoexternalaccount.search', $data);
    return [] if (!$result->{result});

    my @phab_ids;
    foreach my $user (@{ $result->{result} }) {
        push(@phab_ids, $user->{phid})
          if ($user->{phid} && $user->{phid} =~ /^PHID-USER/);
    }

    return \@phab_ids;
}

sub request {
    my ($method, $data) = @_;
    my $request_cache = Bugzilla->request_cache;
    my $params        = Bugzilla->params;

    my $ua = $request_cache->{phabricato_ua};
    unless ($ua) {
        $ua = $request_cache->{phabricator_ua} = LWP::UserAgent->new(timeout => 10);
        if ($params->{proxy_url}) {
            $ua->proxy('https', $params->{proxy_url});
        }
        $ua->default_header('Content-Type' => 'application/x-www-form-urlencoded');
    }

    my $phab_api_key  = $params->{phabricator_api_key};
    my $phab_base_uri = $params->{phabricator_base_uri};
    ThrowUserError('invalid_phabricator_uri') unless $phab_base_uri;
    ThrowUserError('invalid_phabricator_api_key') unless $phab_api_key;

    my $full_uri = $phab_base_uri . '/api/' . $method;

    $data->{__conduit__} = { token => $phab_api_key };

    my $response = $ua->post($full_uri, { params => encode_json($data) });

    ThrowCodeError('phabricator_api_error', { reason => $response->message })
        if $response->is_error;

    my $result = decode_json($response->content);
    if ($result->{error_code}) {
        ThrowCodeError('phabricator_api_error',
                       { code   => $result->{error_code},
                         reason => $result->{error_info} });
    }

    return $result;
}

1;
