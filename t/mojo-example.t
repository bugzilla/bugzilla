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

BEGIN {
    $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
    # There's a plugin called Hostage that makes the application require specific Host: headers.
    # we disable that for these tests.
    $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

# this provides a default urlbase.
# Most localconfig options the other Bugzilla::Test::Mock* modules take care for us.
use Bugzilla::Test::MockLocalconfig ( urlbase => 'http://bmo-web.vm' );

# This configures an in-memory sqlite database.
use Bugzilla::Test::MockDB;

# This redirects reads and writes from the config file (data/params)
use Bugzilla::Test::MockParams (
    phabricator_enabled => 1,
    announcehtml        => '<div id="announcement">Mojo::Test is awesome</div>',
);

# Util provides a few functions more making mock data in the DB.
use Bugzilla::Test::Util qw(create_user issue_api_key);

use Test2::V0;
use Test2::Tools::Mock;
use Test::Mojo;

my $api_user = create_user('api@mozilla.org', '*');
my $api_key  = issue_api_key('api@mozilla.org')->api_key;

# Mojo::Test loads the application and provides methods for
# testing requests without having to run a server.
my $t = Test::Mojo->new('Bugzilla::Quantum');

# we ensure this file exists so the /__lbhearbeat__ test passes.
$t->app->home->child('__lbheartbeat__')->spurt('httpd OK');

# Method chaining is used extensively.
$t->get_ok('/__lbheartbeat__')->status_is(200)->content_is('httpd OK');

# this won't work until we can mock memcached.
# $t->get_ok('/__heartbeat__')->status_is(200);

# we can use json_is or json_like to check APIs.
# The first pair to json_like is a JSON pointer (RFC 6901)
$t->get_ok('/bzapi/configuration')->status_is(200)->json_like( '/announcement' => qr/Mojo::Test is awesome/ );

# for web requests, you use text_like (or text_is) with CSS selectors.
$t->get_ok('/')->status_is(200)->text_like( '#announcement' => qr/Mojo::Test is awesome/ );

# Chaining is not magical, you can break up longer lines
# by calling methods on $t, as below.
$t->get_ok('/rest/whoami' => { 'X-Bugzilla-API-Key' => $api_key });
$t->status_is(200);
$t->json_is('/name' => $api_user->login);
$t->json_is('/id' => $api_user->id);

# Each time you call $t->get_ok, post_ok, etc the previous request is cleared.
$t->get_ok('/rest/whoami');
$t->status_is(200);
$t->json_is('/name' => '');
$t->json_is('/id' => 0);

done_testing;
