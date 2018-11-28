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
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');
use Bugzilla::Test::Util qw(create_user create_oauth_client);

use Test2::V0;
use Test::Mojo;

my $oauth_login    = 'oauth@mozilla.bugs';
my $oauth_password = 'password123456789!';
my $referer        = Bugzilla->localconfig->{urlbase};
my $stash          = {};

# Create user to use as OAuth2 resource owner
create_user($oauth_login, $oauth_password);

# Create a new OAuth2 client used for testing
my $oauth_client = create_oauth_client('Shiny New OAuth Client', ['user:read']);
ok $oauth_client->{id}, 'New client id (' . $oauth_client->{id} . ')';
ok $oauth_client->{secret}, 'New client secret (' . $oauth_client->{secret} . ')';

my $t = Test::Mojo->new('Bugzilla::Quantum');

# Allow 1 redirect max
$t->ua->max_redirects(1);

# Custom routes and hooks required to support running the tests
_setup_routes($t->app->routes);
$t->app->hook(after_dispatch => sub { $stash = shift->stash });

# User should be logged out so /oauth/authorize should redirect to a login screen
$t->get_ok(
  '/oauth/authorize' => {Referer => $referer} => form => {
    client_id     => $oauth_client->{id},
    response_type => 'code',
    state         => 'state',
    scope         => 'user:read',
    redirect_uri  => '/oauth/redirect'
  }
)->status_is(200)
  ->element_exists('div.login-form input[name=Bugzilla_login_token]')
  ->text_is('html head title' => 'Log in to Bugzilla');

# Login the user in using the resource owner username and password
# Once logged in, we should automatically be redirected to the confirm
# scopes page.
$t->post_ok(
  '/login' => {Referer => $referer} => form => {
    Bugzilla_login         => $oauth_login,
    Bugzilla_password      => $oauth_password,
    Bugzilla_restrictlogin => 1,
    GoAheadAndLogIn        => 1,
    client_id              => $oauth_client->{id},
    response_type          => 'code',
    state                  => 'state',
    scope                  => 'user:read',
    redirect_uri           => '/oauth/redirect'
  }
)->status_is(200)->text_is('title' => 'Confirm OAuth2 Scopes');

# Get the csrf token to allow submitting the scope confirmation form
my $csrf_token = $t->tx->res->dom->at('input[name=token]')->val;
ok $csrf_token, "Get csrf token ($csrf_token)";

# Redirect and get the auth code needed for obtaining an access token
# Once we accept the scopes requested, we should get redirected to the
# URI specified in the redirect_uri value. In this case a simple text page.
$t->get_ok(
  '/oauth/authorize' => {Referer => $referer} => form => {
    "oauth_confirm_" . $oauth_client->{id} => 1,
    token                                  => $csrf_token,
    client_id                              => $oauth_client->{id},
    response_type                          => 'code',
    state                                  => 'state',
    scope                                  => 'user:read',
    redirect_uri                           => '/oauth/redirect'
  }
)->status_is(200)->content_is('Redirect Success!');

# The redirect page (normally an external site associated with the
# OAuth2 client) should verify the state token and also get a temporary
# auth code that will be used to request an access token.
my $state = $stash->{state};
ok $state eq 'state', "State was returned correctly";
my $auth_code = $stash->{auth_code};
ok $auth_code, "Get auth code ($auth_code)";

# Contact the OAuth2 server using the auth code to obtain an access token
# This happens as a backend POST the the server and is not visible to the
# end user.
$t->post_ok(
  '/oauth/access_token' => {Referer => $referer} => form => {
    client_id     => $oauth_client->{id},
    client_secret => $oauth_client->{secret},
    code          => $auth_code,
    grant_type    => 'authorization_code',
    redirect_uri  => '/oauth/redirect',
  }
)->status_is(200)->json_has('access_token', 'Has access token')
  ->json_has('refresh_token', 'Has refresh token')
  ->json_has('token_type',    'Has token type');

my $access_data = $t->tx->res->json;

# Using the access token (bearer) we are able to authenticate for an API call.

# 1. Access API unauthenticated and should generate a login_required error
$t->get_ok('/api/user/profile')->status_is(401);

# 2. Passing a Bearer header containing the access token, the server should
# allow us to get data about our user
$t->get_ok('/api/user/profile' =>
    {Authorization => 'Bearer ' . $access_data->{access_token}})
  ->status_is(200)->json_is('/login' => $oauth_login);

done_testing;

sub _setup_routes {
  my $r = shift;

  # Add /oauth/redirect route for checking final redirection
  $r->get(
    '/oauth/redirect' => sub {
      my $c = shift;
      $c->stash(state => $c->param('state'), auth_code => $c->param('code'));
      $c->render(status => 200, text => 'Redirect Success!');
      return;
    }
  );
}

