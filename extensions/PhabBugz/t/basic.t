#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );
use Bugzilla;

BEGIN { Bugzilla->extensions };

use Test::More;
use Test2::Tools::Mock;
use Data::Dumper;
use JSON::MaybeXS;
use Carp;
use Try::Tiny;

use ok 'Bugzilla::Extension::PhabBugz::Feed';
use ok 'Bugzilla::Extension::PhabBugz::Util', qw( get_attachment_revisions );
can_ok('Bugzilla::Extension::PhabBugz::Feed', 'group_query');

our @group_members;
our @project_members;


my $User = mock 'Bugzilla::Extension::PhabBugz::User' => (
    add_constructor => [
        'fake_new' => 'hash',
    ],
    override => [
        'match' => sub { [ mock() ] },
    ],
);

my $Feed = mock 'Bugzilla::Extension::PhabBugz::Feed' => (
    override => [
        get_group_members => sub {
            return [ map { Bugzilla::Extension::PhabBugz::User->fake_new(%$_) } @group_members ];
        }
    ]
);

my $Project = mock 'Bugzilla::Extension::PhabBugz::Project' => (
    override_constructor => [
        new_from_query => 'ref_copy',
    ],
    override => [
        'members' => sub {
            return [ map { Bugzilla::Extension::PhabBugz::User->fake_new(%$_) } @project_members ];
        }
    ]
);

local Bugzilla->params->{phabricator_enabled} = 1;
local Bugzilla->params->{phabricator_api_key} = 'FAKE-API-KEY';
local Bugzilla->params->{phabricator_base_uri} = 'http://fake.fabricator.tld';

my $Bugzilla = mock 'Bugzilla' => (
    override => [
        'dbh'  => sub { mock() },
        'user' => sub { Bugzilla::User->new({ name => 'phab-bot@bmo.tld' }) },
    ],
);

my $BugzillaGroup = mock 'Bugzilla::Group' => (
    add_constructor => [
        'fake_new' => 'hash',
    ],
    override => [
        'match' => sub { [ Bugzilla::Group->fake_new(id => 1, name => 'firefox-security' ) ] },
    ],
);

my $BugzillaUser = mock 'Bugzilla::User' => (
    add_constructor => [
        'fake_new' => 'hash',
    ],
    override => [
        'new' => sub {
            my ($class, $hash) = @_;
            if ($hash->{name} eq 'phab-bot@bmo.tld') {
                return $class->fake_new( id => 8_675_309, login_name => 'phab-bot@bmo.tld', realname => 'Fake PhabBot' );
            }
            else {
            }
        },
        'match' => sub { [ mock() ] },
    ],
);


my $feed = Bugzilla::Extension::PhabBugz::Feed->new;

# Same members in both
do {
    my $UserAgent = mock 'LWP::UserAgent' => (
        override => [
            'post' => sub {
                my ($self, $url, $params) = @_;
                my $data = decode_json($params->{params});
                is_deeply($data->{transactions}, [], 'no-op');
                return mock({is_error => 0, content => '{}'});
            },
        ],
    );
    local @group_members = (
        { phid => 'foo' },
    );
    local @project_members = (
        { phid => 'foo' },
    );
    $feed->group_query;
};

# Project has members not in group
do {
    my $UserAgent = mock 'LWP::UserAgent' => (
        override => [
            'post' => sub {
                my ($self, $url, $params) = @_;
                my $data = decode_json($params->{params});
                my $expected = [ { type => 'members.remove', value => ['foo'] } ];
                is_deeply($data->{transactions}, $expected, 'remove foo');
                return mock({is_error => 0, content => '{}'});
            },
        ]
    );
    local @group_members = ();
    local @project_members = (
        { phid => 'foo' },
    );
    $feed->group_query;
};

# Group has members not in project
do {
    my $UserAgent = mock 'LWP::UserAgent' => (
        override => [
            'post' => sub {
                my ($self, $url, $params) = @_;
                my $data = decode_json($params->{params});
                my $expected = [ { type => 'members.add', value => ['foo'] } ];
                is_deeply($data->{transactions}, $expected, 'add foo');
                return mock({is_error => 0, content => '{}'});
            },
        ]
    );
    local @group_members = (
        { phid => 'foo' },
    );
    local @project_members = (
    );
    $feed->group_query;
};

do {
    my $Revision  = mock 'Bugzilla::Extension::PhabBugz::Revision' => (
        override => [
            'update' => sub { 1 },
        ],
    );
    my $UserAgent = mock 'LWP::UserAgent' => (
        override => [
            'post' => sub {
                my ($self, $url, $params) = @_;
                if ($url =~ /differential\.revision\.search/) {
                    my $content = <<JSON;
{
    "error_info": null,
    "error_code": null,
    "result": {
        "data": [
            {
                "id": 9999,
                "type": "DREV",
                "phid": "PHID-DREV-uozm3ggfp7e7uoqegmc3",
                "fields": {
                    "title": "Added .arcconfig",
                    "summary": "Added .arcconfig",
                    "authorPHID": "PHID-USER-4wigy3sh5fc5t74vapwm",
                    "dateCreated": 1507666113,
                    "dateModified": 1508514027,
                    "policy": {
                        "view": "public",
                        "edit": "admin"
                    },
                    "bugzilla.bug-id": "23",
                    "status": {
                        "value": "needs-review",
                        "name": "Needs Review",
                        "closed": false,
                        "color.ansi": "magenta"
                    }
                },
                "attachments": {
                    "reviewers": {
                        "reviewers": []
                    },
                    "subscribers": {
                        "subscriberPHIDs": [],
                        "subscriberCount": 0,
                        "viewerIsSubscribed": true
                    },
                    "projects": {
                        "projectPHIDs": []
                    }
                }
            }
        ]
    }
}
JSON
                    return mock { is_error => 0, content => $content };
                }
                else {
                    return mock { is_error => 1, message => "bad request" };
                }
            },
        ],
    );
    my $bug = mock {
        bug_id => 23,
        attachments => [
            mock {
                contenttype => 'text/x-phabricator-request',
                filename => 'phabricator-D9999-url.txt',
            },
        ]
    };
    my $revisions = get_attachment_revisions($bug);
    is(ref($revisions), 'ARRAY', 'it is an array ref');
    isa_ok($revisions->[0], 'Bugzilla::Extension::PhabBugz::Revision');
    is($revisions->[0]->bug_id, 23, 'Bugzila ID is 23');
    ok( try { $revisions->[0]->update }, 'update revision');

};

done_testing;