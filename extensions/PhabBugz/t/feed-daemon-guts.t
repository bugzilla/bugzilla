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
use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams;
use Bugzilla::Test::Util qw(create_user);
use Test::More;
use Test2::Tools::Mock;
use Try::Tiny;
use JSON::MaybeXS;
use Bugzilla::Constants;
use URI;
use File::Basename;
use Digest::SHA qw(sha1_hex);

use ok 'Bugzilla::Extension::PhabBugz::Feed';
use ok 'Bugzilla::Extension::PhabBugz::Constants', 'PHAB_AUTOMATION_USER';
use ok 'Bugzilla::Config', 'SetParam';
can_ok('Bugzilla::Extension::PhabBugz::Feed', qw( group_query feed_query user_query ));

Bugzilla->error_mode(ERROR_MODE_TEST);

my $phab_bot = create_user(PHAB_AUTOMATION_USER, '*');

my $UserAgent = mock 'LWP::UserAgent' => ();

{
    SetParam('phabricator_enabled', 0);
    my $feed = Bugzilla::Extension::PhabBugz::Feed->new;
    my $Feed = mock 'Bugzilla::Extension::PhabBugz::Feed' => (
        override => [
            get_last_id => sub { die "get_last_id" },
        ],
    );

    foreach my $method (qw( feed_query user_query group_query )) {
        try {
            $feed->$method;
            pass "disabling the phabricator sync: $method";
        }
        catch {
            fail "disabling the phabricator sync: $method";
        }
    }
}

my @bad_response = (
    ['http error', mock({ is_error => 1, message => 'some http error' }) ],
    ['invalid json', mock({ is_error => 0, content => '<xml>foo</xml>' })],
    ['json containing error code', mock({ is_error => 0, content => encode_json({error_code => 1234 }) })],
);

SetParam(phabricator_enabled => 1);
SetParam(phabricator_api_key => 'FAKE-API-KEY');
SetParam(phabricator_base_uri => 'http://fake.fabricator.tld/');

foreach my $bad_response (@bad_response) {
    my $feed = Bugzilla::Extension::PhabBugz::Feed->new;
    $UserAgent->override(
        post => sub {
            my ( $self, $url, $params ) = @_;
            return $bad_response->[1];
        }
    );

    foreach my $method (qw( feed_query user_query group_query )) {
        try {
            # This is a hack to get reasonable exception objects.
            local $Bugzilla::Template::is_processing = 1;
            $feed->$method;
            fail "$method - $bad_response->[0]";
        }
        catch {
            is( $_->type, 'bugzilla.code.phabricator_api_error', "$method - $bad_response->[0]" );
        };
    }
    $UserAgent->reset('post');
}

my $feed      = Bugzilla::Extension::PhabBugz::Feed->new;
my $json      = JSON::MaybeXS->new( canonical => 1, pretty => 1 );
my $dylan     = create_user( 'dylan@mozilla.com', '*', realname => 'Dylan Hardison :dylan' );
my $evildylan = create_user( 'dylan@gmail.com', '*', realname => 'Evil Dylan :dylan' );
my $myk       = create_user( 'myk@mozilla.com', '*', realname => 'Myk Melez :myk' );

my $phab_bot_phid = next_phid('PHID-USER');

done_testing;

sub user_search {
    my (%conf) = @_;

    return {
        error_info => undef,
        error_code => undef,
        result     => {
            cursor => {
                after  => $conf{after},
                order  => undef,
                limit  => 100,
                before => undef
            },
            query => {
                queryKey => undef
            },
            maps => {},
            data => [
                map {
                    +{
                        attachments => {
                            $_->{bmo_id}
                            ? ( "external-accounts" => {
                                    "external-accounts" => [
                                        {
                                            type => 'bmo',
                                            id   => $_->{bmo_id},
                                        }
                                    ]
                                }
                              )
                            : (),
                        },
                        fields => {
                            roles        => [ "verified", "approved", "activated" ],
                            realName     => $_->{realname},
                            dateModified => time,
                            policy       => {
                                view => "public",
                                edit => "no-one"
                            },
                            dateCreated => time,
                            username    => $_->{username},
                        },
                        phid => next_phid("PHID-USER"),
                        type => "USER",
                        id   => $_->{phab_id},
                      },
                } @{ $conf{users} },
            ]
        }
    };

}

sub next_phid {
    my ($prefix) = @_;
    state $number = 'a' x 20;
    return $prefix . '-' .  ($number++);
}


