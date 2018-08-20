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
BEGIN { $ENV{LOG4PERL_CONFIG_FILE} = 'log4perl-t.conf' }
use Test2::V0;

our @EMAILS;

BEGIN {
    require Bugzilla::Mailer;
    no warnings 'redefine';
    *Bugzilla::Mailer::MessageToMTA = sub {
        push @EMAILS, [@_];
    };
}
use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams;
use Bugzilla::Test::Util qw(create_user);
use Test2::Tools::Mock;
use Try::Tiny;
use JSON::MaybeXS;
use Bugzilla::Constants;
use URI;
use File::Basename;
use Digest::SHA qw(sha1_hex);
use Data::Dumper;

use ok 'Bugzilla::Extension::PhabBugz::Feed';
use ok 'Bugzilla::Extension::PhabBugz::Constants', 'PHAB_AUTOMATION_USER';
use ok 'Bugzilla::Config', 'SetParam';
can_ok('Bugzilla::Extension::PhabBugz::Feed', qw( group_query feed_query user_query ));

SetParam(phabricator_base_uri => 'http://fake.phabricator.tld/');
SetParam(mailfrom => 'bugzilla-daemon');
Bugzilla->error_mode(ERROR_MODE_TEST);
my $nobody = create_user('nobody@mozilla.org', '*');
my $phab_bot = create_user(PHAB_AUTOMATION_USER, '*');

# Steve Rogers is the revision author
my $steve = create_user('steverogers@avengers.org', '*', realname => 'Steve Rogers :steve');

# Bucky Barns is the reviewer
my $bucky = create_user('bucky@avengers.org', '*', realname => 'Bucky Barns :bucky');

my $firefox = Bugzilla::Product->create(
    {
        name => 'Firefox',
        description => 'Fake firefox product',
        version => 'Unspecified',
    },
);

my $general = Bugzilla::Component->create(
    {
        product =>$firefox,
        name => 'General',
        description => 'The most general description',
        initialowner => { id => $nobody->id },
    }
);

Bugzilla->set_user($steve);
my $bug = Bugzilla::Bug->create(
    {
        short_desc   => 'test bug',
        product      => $firefox,
        component    => $general->name,
        bug_severity => 'normal',
        op_sys       => 'Unspecified',
        rep_platform => 'Unspecified',
        version      => 'Unspecified',
        comment      => 'first post',
        priority     => 'P1',
    }
);

my $recipients = { changer => $steve };
Bugzilla::BugMail::Send($bug->bug_id, $recipients);
@EMAILS = ();

my $revision = Bugzilla::Extension::PhabBugz::Revision->new(
    {
        id           => 1,
        phid         => 'PHID-DREV-uozm3ggfp7e7uoqegmc3',
        type         => 'DREV',
        fields => {
            title        => "title",
            summary      => "the summary of the revision",
            status       => { value => "not sure" },
            dateCreated  => time() - (60 * 60),
            dateModified => time() - (60 * 5),
            authorPHID   => 'authorPHID',
            policy       => {
                view => 'policy.view',
                edit => 'policy.edit',
            },
            'bugzilla.bug-id' => $bug->id,
        },
        attachments => {
            projects => { projectPHIDs => [] },
            reviewers => {
                reviewers => [ ],
            },
            subscribers => {
                subscriberPHIDs => [],
                subscriberCount => 1,
                viewerIsSubscribed => 1,
            }
        },
        reviews => [
            {
                user => new_phab_user($bucky),
                status => 'accepted',
            }
        ]
    }
);
my $PhabRevisionMock = mock 'Bugzilla::Extension::PhabBugz::Revision' => (
    override => [
        make_public => sub { },
        update => sub { },
    ]
);
my $PhabUserMock = mock 'Bugzilla::Extension::PhabBugz::User' => (
    override => [
        match => sub {
            my ($class, $query) = @_;
            if ($query && $query->{phids} && $query->{phids}[0]) {
                my $phid = $query->{phids}[0];
                if ($phid eq 'authorPHID') {
                    return [ new_phab_user($steve, $phid) ];
                }
            }
        },
    ]
);


my $feed    = Bugzilla::Extension::PhabBugz::Feed->new;
my $changer = new_phab_user($bucky);
@EMAILS = ();
$feed->process_revision_change(
    $revision, $changer, "story text"
);

# The first comment, and the comment made when the attachment is attached
# are made by Steve.
# The review comment is made by Bucky.

my $sth = Bugzilla->dbh->prepare("select profiles.login_name, thetext from longdescs join profiles on who = userid");
$sth->execute;
while (my $row = $sth->fetchrow_hashref) {
    if ($row->{thetext} =~ /first post/i) {
        is($row->{login_name}, $steve->login, 'first post author');
    }
    elsif ($row->{thetext} =~ /the summary of the revision/i) {
        is($row->{login_name}, $steve->login, 'the first attachment comment');
    }
    elsif ($row->{thetext} =~ /has approved the revision/i) {
        is($row->{login_name}, $bucky->login);
    }
}

diag Dumper(\@EMAILS);

done_testing;

sub new_phab_user {
    my ($bug_user, $phid) = @_;

    return Bugzilla::Extension::PhabBugz::User->new(
        {
            id => $bug_user->id * 1000,
            type => "USER",
            phid => $phid // "PHID-USER-" . ( $bug_user->id * 1000 ),
            fields => {
                username     => $bug_user->nick,
                realName     => $bug_user->name,
                dateCreated  => time() - 60 * 60 * 24,
                dateModified => time(),
                roles        => [],
                policy       => {
                    view => 'view',
                    edit => 'edit',
                },
            },
            attachments => {
                'external-accounts' => {
                    'external-accounts' => [
                        {
                            type => 'bmo',
                            id   => $bug_user->id,
                        }
                    ]
                }
            }
        }
    );


}