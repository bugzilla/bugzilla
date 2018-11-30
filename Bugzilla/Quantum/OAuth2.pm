# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::OAuth2;

use 5.10.1;
use strict;
use warnings;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Util;
use Bugzilla::Token;

use DateTime;

use Mojo::Util qw(secure_compare);

use base qw(Exporter);
our @EXPORT_OK = qw(oauth2);

sub oauth2 {
  my ($self) = @_;

  $self->plugin(
    'OAuth2::Server' => {
      login_resource_owner      => \&_resource_owner_logged_in,
      confirm_by_resource_owner => \&_resource_owner_confirm_scopes,
      verify_client             => \&_verify_client,
      store_auth_code           => \&_store_auth_code,
      verify_auth_code          => \&_verify_auth_code,
      store_access_token        => \&_store_access_token,
      verify_access_token       => \&_verify_access_token,
    }
  );

  # Manage the client list
  my $r            = $self->routes;
  my $client_route = $r->under(
    '/admin/oauth' => sub {
      my ($c) = @_;
      my $user = $c->bugzilla->login(LOGIN_REQUIRED) || return undef;
      $user->in_group('admin')
        || ThrowUserError('auth_failure',
        {group => 'admin', action => 'edit', object => 'oauth_clients'});
      return 1;
    }
  );
  $client_route->any('/list')->to('OAuth2::Clients#list')->name('list_clients');
  $client_route->any('/create')->to('OAuth2::Clients#create')
    ->name('create_client');
  $client_route->any('/delete')->to('OAuth2::Clients#delete')
    ->name('delete_client');
  $client_route->any('/edit')->to('OAuth2::Clients#edit')->name('edit_client');

  $self->helper(
    'bugzilla.oauth' => sub {
        my ($c, @scopes) = @_;

        my $oauth = $c->oauth(@scopes);

        if ($oauth && $oauth->{user_id}) {
          my $user = Bugzilla::User->check({id => $oauth->{user_id}, cache => 1});
          Bugzilla->set_user($user);
          return $user;
        }

        return undef;
    }
  );

  return 1;
}

sub _resource_owner_logged_in {
  my (%args) = @_;
  my $c = $args{mojo_controller};

  $c->session->{override_login_target} = $c->url_for('current');
  $c->session->{cgi_params} = $c->req->params->to_hash;

  $c->bugzilla->login(LOGIN_REQUIRED) || return;

  delete $c->session->{override_login_target};
  delete $c->session->{cgi_params};

  return 1;
}

sub _resource_owner_confirm_scopes {
  my (%args) = @_;
  my ($c, $client_id, $scopes_ref)
    = @args{qw/ mojo_controller client_id scopes /};

  my $is_allowed = $c->param("oauth_confirm_${client_id}");

  # if user hasn't yet allowed the client access, or if they denied
  # access last time, we check [again] with the user for access
  if (!defined $is_allowed) {
    my $client
      = Bugzilla->dbh->selectrow_hashref(
      'SELECT * FROM oauth2_client WHERE id = ?',
      undef, $client_id);
    my $vars = {
      client => $client,
      scopes => $scopes_ref,
      token  => scalar issue_session_token('oauth_confirm_scopes')
    };
    $c->stash(%$vars);
    $c->render(
      template => 'account/auth/confirm_scopes',
      handler  => 'bugzilla'
    );
    return undef;
  }

  my $token = $c->param('token');
  check_token_data($token, 'oauth_confirm_scopes');
  delete_token($token);

  return $is_allowed;
}

sub _verify_client {
  my (%args) = @_;
  my ($c, $client_id, $scopes_ref)
    = @args{qw/ mojo_controller client_id scopes /};
  my $dbh = Bugzilla->dbh;

  if (!@{$scopes_ref}) {
    INFO('Client did not provide scopes');
    return (0, 'invalid_scope');
  }

  if (
    my $client_data = $dbh->selectrow_hashref(
      'SELECT * FROM oauth2_client WHERE id = ?',
      undef, $client_id
    )
    )
  {
    if (!$client_data->{active}) {
      INFO("Client ($client_id) is not active");
      return (0, 'unauthorized_client');
    }

    foreach my $rqd_scope (@{$scopes_ref}) {
      my $scope_allowed = $dbh->selectrow_array(
        'SELECT allowed FROM oauth2_client_scope
                JOIN oauth2_scope ON oauth2_scope.id = oauth2_client_scope.scope_id
          WHERE client_id = ? AND oauth2_scope.description = ?', undef,
        $client_id, $rqd_scope
      );
      if (defined $scope_allowed) {
        if (!$scope_allowed) {
          INFO("Client disallowed scope ($rqd_scope)");
          return (0, 'access_denied');
        }
      }
      else {
        INFO("Client lacks scope ($rqd_scope)");
        return (0, 'invalid_scope');
      }
    }

    return (1);
  }

  INFO("Client ($client_id) does not exist");
  return (0, 'unauthorized_client');
}

sub _store_auth_code {
  my (%args) = @_;
  my ($c, $auth_code, $client_id, $expires_in, $uri, $scopes_ref)
    = @args{
    qw/ mojo_controller auth_code client_id expires_in redirect_uri scopes /};
  my $dbh = Bugzilla->dbh;

  my $user_id = Bugzilla->user->id;

  $dbh->do(
    'INSERT INTO oauth2_auth_code VALUES (?, ?, ?, ?, ?, 0)',
    undef,
    $auth_code,
    $client_id,
    Bugzilla->user->id,
    DateTime->from_epoch(epoch => time + $expires_in),
    $uri
  );

  foreach my $rqd_scope (@{$scopes_ref}) {
    my $scope_id
      = $dbh->selectrow_array(
      'SELECT id FROM oauth2_scope WHERE description = ?',
      undef, $rqd_scope);
    if ($scope_id) {
      $dbh->do('INSERT INTO oauth2_auth_code_scope VALUES (?, ?, 1)',
        undef, $auth_code, $scope_id);
    }
    else {
      ERROR("Unknown scope ($rqd_scope) in _store_auth_code");
    }
  }

  return;
}

sub _verify_auth_code {
  my (%args) = @_;
  my ($c, $client_id, $client_secret, $auth_code, $uri)
    = @args{
    qw/ mojo_controller client_id client_secret auth_code redirect_uri /};
  my $dbh = Bugzilla->dbh;

  my $client_data
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE id = ?',
    undef, $client_id);
  $client_data || return (0, 'unauthorized_client');

  my $auth_code_data = $dbh->selectrow_hashref(
    'SELECT expires, verified, redirect_uri, user_id FROM oauth2_auth_code WHERE client_id = ? AND auth_code = ?',
    undef, $client_id, $auth_code
  );

  if (!$auth_code_data
    or $auth_code_data->{verified}
    or ($uri ne $auth_code_data->{redirect_uri})
    or (datetime_from($auth_code_data->{expires})->epoch <= time)
    or !secure_compare($client_secret, $client_data->{secret}))
  {
    INFO('Auth code does not exist') if !$auth_code;
    INFO('Client secret does not match')
      if !secure_compare($client_secret, $client_data->{secret});

    if ($auth_code) {
      INFO('Client secret does not match')
        if ($uri && $auth_code_data->{redirect_uri} ne $uri);
      INFO('Auth code expired') if ($auth_code_data->{expires} <= time);

      if ($auth_code_data->{verified}) {

        # the auth code has been used before - we must revoke the auth code
        # and any associated access tokens (same client_id and user_id)
        INFO( 'Auth code already used to get access token, '
            . 'revoking all associated access tokens');
        $dbh->do('DELETE FROM oauth2_auth_code WHERE auth_code = ?',
          undef, $auth_code);
        $dbh->do(
          'DELETE FROM oauth2_access_token WHERE client_id = ? AND user_id = ?',
          undef, $client_id, $auth_code_data->{user_id}
        );
      }
    }

    return (0, 'invalid_grant');
  }

  $dbh->do('UPDATE oauth2_auth_code SET verified = 1 WHERE auth_code = ?',
    undef, $auth_code);

  # scopes are those that were requested in the authorization request, not
  # those stored in the client (i.e. what the auth request restriced scopes
  # to and not everything the client is capable of)
  my $scope_descriptions = $dbh->selectcol_arrayref(
    'SELECT oauth2_scope.description FROM oauth2_scope
            JOIN oauth2_auth_code_scope ON oauth2_scope.id = oauth2_auth_code_scope.scope_id
      WHERE oauth2_auth_code_scope.auth_code = ?', undef, $auth_code
  );

  my %scope = map { $_ => 1 } @{$scope_descriptions};

  return ($client_id, undef, {%scope}, $auth_code_data->{user_id});
}

sub _store_access_token {
  my (%args) = @_;
  my ($c, $client, $auth_code, $access_token, $refresh_token, $expires_in,
    $scopes, $old_refresh_token)
    = @args{
    qw/ mojo_controller client_id auth_code access_token refresh_token expires_in scopes old_refresh_token /
    };
  my $dbh = Bugzilla->dbh;
  my ($user_id);

  if (!defined $auth_code && $old_refresh_token) {
    # must have generated an access token via a refresh token so revoke the
    # old access token and refresh token (also copy required data if missing)
    my $prev_refresh_token
      = $dbh->selectrow_hashref(
      'SELECT * FROM oauth2_refresh_token WHERE refresh_token = ?',
      undef, $old_refresh_token);
    my $prev_access_token
      = $dbh->selectrow_hashref(
      'SELECT * FROM oauth2_access_token WHERE access_token = ?',
      undef, $prev_refresh_token->{access_token});

    # access tokens can be revoked, whilst refresh tokens can remain so we
    # need to get the data from the refresh token as the access token may
    # no longer exist at the point that the refresh token is used
    my $scope_descriptions = $dbh->selectall_array(
      'SELECT oauth2_scope.description FROM oauth2_scope
              JOIN oauth2_access_token_scope ON scope.id = oauth2_access_token_scope.scope_id
        WHERE access_token = ?', undef, $old_refresh_token
    );
    $scopes //= map { $_ => 1 } @{ $scope_descriptions };

    $user_id = $prev_refresh_token->{user_id};
  }
  else {
    $user_id
      = $dbh->selectrow_array(
      'SELECT user_id FROM oauth2_auth_code WHERE auth_code = ?',
      undef, $auth_code);
  }

  if (ref $client) {
    $scopes //= $client->{scope};
    $user_id //= $client->{user_id};
    $client = $client->{client_id};
  }

  foreach my $token_type (qw/ access refresh /) {
    my $table = "oauth2_${token_type}_token";

    # if the client has en existing access/refresh token we need to revoke it
    $dbh->do("DELETE FROM $table WHERE client_id = ? AND user_id = ?",
      undef, $client, $user_id);
  }

  $dbh->do(
    'INSERT INTO oauth2_access_token VALUES (?, ?, ?, ?, ?)', undef,
    $access_token,                                            $refresh_token,
    $client,                                                  $user_id,
    DateTime->from_epoch(epoch => time + $expires_in)
  );

  $dbh->do('INSERT INTO oauth2_refresh_token VALUES (?, ?, ?, ?)',
    undef, $refresh_token, $access_token, $client, $user_id);

  foreach my $rqd_scope (keys %{$scopes}) {
    my $scope_id
      = $dbh->selectrow_array(
      'SELECT id FROM oauth2_scope WHERE description = ?',
      undef, $rqd_scope);
    if ($scope_id) {
      foreach my $related (qw/ access_token refresh_token /) {
        my $table = "oauth2_${related}_scope";
        $dbh->do(
          "INSERT INTO $table VALUES (?, ?, ?)",
          undef,
          $related eq 'access_token' ? $access_token : $refresh_token,
          $scope_id,
          $scopes->{$rqd_scope}
        );
      }
    }
    else {
      ERROR("Unknown scope ($rqd_scope) in _store_access_token");
    }
  }

  return;
}

sub _verify_access_token {
  my (%args) = @_;
  my ($c, $access_token, $scopes_ref)
    = @args{qw/ mojo_controller access_token scope /};
  my $dbh = Bugzilla->dbh;

  if (
    my $refresh_token_data = $dbh->selectrow_hashref(
      'SELECT * FROM oauth2_refresh_token WHERE access_token = ?', undef,
      $access_token
    )
    )
  {
    foreach my $scope (@{$scopes_ref // []}) {
      my $scope_allowed = $dbh->selectrow_array(
        'SELECT allowed FROM oauth2_refresh_token_scope
                JOIN oauth2_scope ON oauth2_scope.id = oauth2_refresh_token_scope.scope_id
          WHERE refresh_token = ? AND oauth2_scope.description = ?', undef,
        $access_token, $scope
      );

      if (!defined $scope_allowed || !$scope_allowed) {
        INFO("Refresh token doesn't have scope ($scope)");
        return (0, 'invalid_grant');
      }
    }

    return {
      client_id => $refresh_token_data->{client_id},
      user_id   => $refresh_token_data->{user_id},
    };
  }
  elsif (
    my $access_token_data = $dbh->selectrow_hashref(
      'SELECT expires, client_id, user_id FROM oauth2_access_token WHERE access_token = ?',
      undef,
      $access_token
    )
    )
  {
    if (datetime_from($access_token_data->{expires})->epoch <= time) {
      INFO('Access token has expired');
      $dbh->do('DELETE FROM oauth2_access_token WHERE access_token = ?',
        undef, $access_token);
      return (0, 'invalid_grant');
    }

    foreach my $scope (@{$scopes_ref // []}) {
      my $scope_allowed = $dbh->selectrow_array(
        'SELECT allowed FROM oauth2_access_token_scope
                JOIN oauth2_scope ON oauth2_access_token_scope.scope_id = oauth2_scope.id
          WHERE scope.description = ? AND access_token = ?', undef, $scope,
        $access_token
      );
      if (!defined $scope_allowed || !$scope_allowed) {
        INFO("Access token doesn't have scope ($scope)");
        return (0, 'invalid_grant');
      }
    }

    return {
      client_id => $access_token_data->{client_id},
      user_id   => $access_token_data->{user_id},
    };
  }
  else {
    INFO('Access token does not exist');
    return (0, 'invalid_grant');
  }
}

1;
