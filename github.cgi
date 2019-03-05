#!/usr/bin/env perl
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
use Bugzilla::Util qw(remote_ip);
use Bugzilla::Error;
use Bugzilla::Constants;
use Bugzilla::Token qw( issue_short_lived_session_token
  set_token_extra_data
  get_token_extra_data
  delete_token );
use URI;
use URI::QueryParam;
BEGIN { Bugzilla->extensions }
use Bugzilla::Extension::GitHubAuth::Client;

my $cgi     = Bugzilla->cgi;
my $urlbase = Bugzilla->localconfig->{urlbase};

if (lc($cgi->request_method) eq 'post') {

  # POST requests come from Bugzilla itself and begin the GitHub login process
  # by redirecting the user to GitHub's authentication endpoint.

  my $user       = Bugzilla->login(LOGIN_OPTIONAL);
  my $target_uri = $cgi->param('target_uri')
    or ThrowCodeError("github_invalid_target");
  my $github_secret = $cgi->param('github_secret')
    or ThrowCodeError("github_invalid_request", {reason => 'invalid secret'});
  my $github_secret2 = Bugzilla->github_secret
    or ThrowCodeError("github_invalid_request", {reason => 'invalid secret'});

  if ($github_secret ne $github_secret2) {
    Bugzilla->check_rate_limit('github', remote_ip());
    ThrowCodeError("github_invalid_request", {reason => 'invalid secret'});
  }

  ThrowCodeError("github_invalid_target", {target_uri => $target_uri})
    unless $target_uri =~ /^\Q$urlbase\E/;

  ThrowCodeError("github_insecure_referer", {target_uri => $target_uri})
    if $cgi->referer
    && $cgi->referer =~ /(?:reset_password\.cgi|token\.cgi|\bt=|token=|api_key=)/;

  if ($user->id) {
    print $cgi->redirect($target_uri);
    exit;
  }

  my $state = issue_short_lived_session_token("github_state");
  set_token_extra_data($state,
    {type => 'github_login', target_uri => $target_uri});

  $cgi->send_cookie(-name => 'github_state', -value => $state, -httponly => 1);
  print $cgi->redirect(
    Bugzilla::Extension::GitHubAuth::Client->authorize_uri($state));
}
elsif (lc($cgi->request_method) eq 'get') {

  # GET requests come from GitHub, with this script acting as the OAuth2 callback.
  my $state_param  = $cgi->param('state');
  my $state_cookie = $cgi->cookie('github_state');

  # If the state or params are missing, or the github_state cookie is missing
  # we just redirect to the homepage.
  unless ($state_param
    && $state_cookie
    && ($cgi->param('code') || $cgi->param('email')))
  {
    $cgi->base_redirect();
  }

  my $invalid_request = $state_param ne $state_cookie;

  my $state_data;
  unless ($invalid_request) {
    $state_data = get_token_extra_data($state_param);
    $invalid_request
      = !($state_data
      && $state_data->{type}
      && $state_data->{type} =~ /^github_(?:login|email)$/);
  }

  if ($invalid_request) {
    Bugzilla->check_rate_limit('github', remote_ip());
    ThrowCodeError("github_invalid_request", {reason => 'invalid state param'});
  }

  $cgi->remove_cookie('github_state');
  delete_token($state_param);

  if ($state_data->{type} eq 'github_login') {
    Bugzilla->request_cache->{github_action}     = 'login';
    Bugzilla->request_cache->{github_target_uri} = $state_data->{target_uri};
  }
  elsif ($state_data->{type} eq 'github_email') {
    Bugzilla->request_cache->{github_action} = 'email';
    Bugzilla->request_cache->{github_emails} = $state_data->{emails};
  }
  my $user = Bugzilla->login(LOGIN_REQUIRED);

  my $target_uri = URI->new($state_data->{target_uri});

  # It makes very little sense to login to a page with the logout parameter.
  # doing so would be a no-op, so we ignore the logout param here.
  $target_uri->query_param_delete('logout');

  if ($target_uri->path =~ /attachment\.cgi/) {
    my $attachment_uri = URI->new('attachment.cgi');
    $attachment_uri->query_param(id => scalar $target_uri->query_param('id'));
    if ($target_uri->query_param('action')) {
      $attachment_uri->query_param(
        action => scalar $target_uri->query_param('action'));
    }
    $cgi->base_redirect($attachment_uri->as_string);
  }
  else {
    print $cgi->redirect($target_uri);
  }
}
