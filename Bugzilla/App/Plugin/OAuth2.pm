# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Plugin::OAuth2;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin::OAuth2::Server';

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Util;
use Bugzilla::Token;
use DateTime;
use List::MoreUtils qw(any);
use Mojo::URL;
use Mojo::Util qw(secure_compare);
use Try::Tiny;

use constant TOKEN_TYPE_AUTH    => 0;
use constant TOKEN_TYPE_ACCESS  => 1;
use constant TOKEN_TYPE_REFRESH => 2;

sub register {
  my ($self, $app, $conf) = @_;

  $conf->{login_resource_owner}      = \&_resource_owner_logged_in;
  $conf->{confirm_by_resource_owner} = \&_resource_owner_confirm_scopes;
  $conf->{verify_client}             = \&_verify_client;
  $conf->{store_auth_code}           = \&_store_auth_code;
  $conf->{verify_auth_code}          = \&_verify_auth_code;
  $conf->{store_access_token}        = \&_store_access_token;
  $conf->{verify_access_token}       = \&_verify_access_token;
  $conf->{jwt_secret}                = Bugzilla->localconfig->{jwt_secret};
  $conf->{jwt_claims}                = sub {
    my $args = shift;
    if (!$args->{user_id}) {
      return (user_id => Bugzilla->user->id);
    }
  };

  $app->helper(
    'bugzilla.oauth' => sub {
      my ($c, @scopes) = @_;

      my $oauth = $c->oauth(@scopes);

      if ($oauth && $oauth->{user_id}) {
        my $user = Bugzilla::User->check({id => $oauth->{user_id}, cache => 1});
        return undef if !$user->is_enabled;
        Bugzilla->set_user($user);
        return $user;
      }

      return undef;
    }
  );

  return $self->SUPER::register($app, $conf);
}

sub _resource_owner_logged_in {
  my (%args) = @_;
  my $c = $args{mojo_controller};

  $c->session->{override_login_target} = $c->url_for('current');
  $c->session->{cgi_params}            = $c->req->params->to_hash;

  $c->bugzilla->login(LOGIN_REQUIRED) || return undef;

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
      'SELECT * FROM oauth2_client WHERE client_id = ?',
      undef, $client_id);
    my $vars = {
      client => $client,
      scopes => $scopes_ref,
      token  => scalar issue_session_token('oauth_confirm_scopes')
    };
    $c->stash(%{$vars});
    $c->render(template => 'account/auth/confirm_scopes', handler => 'bugzilla');
    return undef;
  }

  my $token = $c->param('token');
  check_token_data($token, 'oauth_confirm_scopes');
  delete_token($token);

  return $is_allowed;
}

sub _verify_client {
  my (%args) = @_;
  my ($c, $client_id, $scopes_ref, $redirect_uri)
    = @args{qw/ mojo_controller client_id scopes redirect_uri /};
  my $dbh = Bugzilla->dbh;

  if (!@{$scopes_ref}) {
    INFO('Client did not provide scopes');
    return (0, 'invalid_scope');
  }

  if (!$ENV{BUGZILLA_ALLOW_INSECURE_HTTP} && Mojo::URL->new($redirect_uri)->scheme ne 'https') {
    INFO("invalid_redirect_uri: $redirect_uri");
    return (0, 'invalid_redirect_uri');
  }

  if (
    my $client_data = $dbh->selectrow_hashref(
      'SELECT * FROM oauth2_client WHERE client_id = ?',
      undef, $client_id
    )
    )
  {
    if (!$client_data->{active}) {
      INFO("Client ($client_id) is not active");
      return (0, 'unauthorized_client');
    }

    if ($scopes_ref) {
      my $client_scopes = $dbh->selectcol_arrayref(
        'SELECT oauth2_scope.description FROM oauth2_scope
                JOIN oauth2_client_scope ON oauth2_scope.id = oauth2_client_scope.scope_id
          WHERE oauth2_client_scope.client_id = ?', undef, $client_data->{id}
      );

      foreach my $scope (@{$scopes_ref // []}) {
        return (0, 'invalid_grant') if !_has_scope($scope, $client_scopes);
      }
    }

    return (1);
  }

  INFO("Client ($client_id) does not exist");
  return (0, 'unauthorized_client');
}

sub _verify_auth_code {
  my (%args) = @_;
  my ($c, $client_id, $client_secret, $auth_code, $uri)
    = @args{qw/ mojo_controller client_id client_secret auth_code redirect_uri /};
  my $dbh = Bugzilla->dbh;

  my $client_data
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE client_id = ?',
    undef, $client_id);
  $client_data || return (0, 'unauthorized_client');

  my ($res, $jwt_claims) = _get_jwt_claims($auth_code, 'auth');
  return (0, 'invalid_jwt') unless $res;

  my $jwt_data = $dbh->selectrow_hashref('SELECT * FROM oauth2_jwt WHERE jti = ?',
    undef, $jwt_claims->{jti});

  if (!$jwt_data
    or ($jwt_data->{type} ne TOKEN_TYPE_AUTH)
    or ($jwt_claims->{user_id} != $jwt_data->{user_id})
    or ($uri ne $jwt_claims->{aud})
    or ($jwt_claims->{exp} <= time)
    or !secure_compare($client_secret, $client_data->{secret}))
  {
    INFO('Client secret does not match')
      if !secure_compare($client_secret, $client_data->{secret});

    if ($jwt_data) {
      INFO('Client redirect_uri does not match')
        if ($uri && $jwt_claims->{aud} ne $uri);
      INFO('Auth code expired') if ($jwt_claims->{exp} <= time);
      $dbh->do('DELETE FROM oauth2_jwt WHERE client_id = ? AND user_id = ? AND type = ?',
          undef, $client_data->{id}, $jwt_claims->{user_id}, TOKEN_TYPE_AUTH);
    }

    return (0, 'invalid_grant');
  }

  $dbh->do('DELETE FROM oauth2_jwt WHERE id = ?',
    undef, $jwt_data->{id});

  return ($client_id, undef, $jwt_claims->{scopes}, $jwt_claims->{user_id});
}

sub _store_auth_code {
  my (%args) = @_;
  my ($c, $auth_code, $client_id, $expires_in, $uri, $scopes_ref)
    = @args{
    qw/ mojo_controller auth_code client_id expires_in redirect_uri scopes /};
  my $dbh = Bugzilla->dbh;

  my $client_data
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE client_id = ?',
    undef, $client_id);

  my ($res, $jwt_claims) = _get_jwt_claims($auth_code, 'auth');
  return (0, 'invalid_jwt') unless $res;

  $dbh->do(
    'INSERT INTO oauth2_jwt (jti, client_id, user_id, type, expires) VALUES (?, ?, ?, ?, ?)',
    undef,
    $jwt_claims->{jti},
    $client_data->{id},
    $jwt_claims->{user_id},
    TOKEN_TYPE_AUTH,
    DateTime->from_epoch(epoch => time + $expires_in),
  );

  return undef;
}

sub _store_access_token {
  my (%args) = @_;
  my ($c, $client_id, $auth_code, $access_token, $refresh_token, $expires_in,
    $scopes, $old_refresh_token)
    = @args{
    qw/ mojo_controller client_id auth_code access_token refresh_token expires_in scopes old_refresh_token /
    };
  my $dbh = Bugzilla->dbh;

  my $client_data
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE client_id = ?',
    undef, $client_id);

  my $user_id;
  if (!defined $auth_code && $old_refresh_token) {
    # must have generated an access token via a refresh token so revoke the
    # old access token and refresh token (also copy required data if missing)
    my ($res, $jwt_claims) = _get_jwt_claims($old_refresh_token, 'refresh');
    return (0, 'invalid_jwt') unless $res;
    my $jwt_data = $dbh->selectrow_hashref('SELECT * FROM oauth2_jwt WHERE jti = ?', undef, $jwt_claims->{jti});
    return (0, 'invalid_grant') if !$jwt_data;
    $user_id = $jwt_claims->{user_id};
  }
  else {
    my ($res, $jwt_claims) = _get_jwt_claims($auth_code, 'auth');
    return (0, 'invalid_jwt') unless $res;
    $user_id = $jwt_claims->{user_id};
  }

  my ($res, $jwt_claims) = _get_jwt_claims($access_token, 'access');
  return (0, 'invalid_jwt') unless $res;

  # If the client has en existing access/refesh tokens, we need to revoke them
  INFO('Revoking old access tokens (refresh)');
  $dbh->do('DELETE FROM oauth2_jwt WHERE client_id = ? AND user_id = ?',
    undef, $client_data->{id}, $jwt_claims->{user_id});

  $dbh->do(
    'INSERT INTO oauth2_jwt (jti, client_id, user_id, type, expires) VALUES (?, ?, ?, ?, ?)',
    undef,
    $jwt_claims->{jti},
    $client_data->{id},
    $user_id,
    TOKEN_TYPE_ACCESS,
    DateTime->from_epoch(epoch => time + $expires_in),
  );

  ($res, $jwt_claims) = _get_jwt_claims($refresh_token, 'refresh');
  return (0, 'invalid_jwt') unless $res;

  $dbh->do(
    'INSERT INTO oauth2_jwt (jti, client_id, user_id, type) VALUES (?, ?, ?, ?)',
    undef,
    $jwt_claims->{jti},
    $client_data->{id},
    $user_id,
    TOKEN_TYPE_REFRESH
  );

  return undef;
}

sub _verify_access_token {
  my (%args) = @_;
  my ($c, $access_token, $scopes_ref, $is_refresh_token)
    = @args{qw/ mojo_controller access_token scopes is_refresh_token /};
  my $dbh = Bugzilla->dbh;

  my ($res, $jwt_claims) = _get_jwt_claims($access_token);
  return (0, 'invalid_jwt') unless $res;

  my $jwt_data = $dbh->selectrow_hashref('SELECT * FROM oauth2_jwt WHERE jti = ?', undef, $jwt_claims->{jti});

  if ($jwt_data && $is_refresh_token) {
    if ($scopes_ref) {
      foreach my $scope (@{$scopes_ref // []}) {
        return (0, 'invalid_grant') if !_has_scope($scope, $jwt_claims->{scopes});
      }
    }

    return ($jwt_claims, undef, $jwt_claims->{scopes}, $jwt_claims->{user_id});
  }

  if ($jwt_data) {
    if ($jwt_claims->{exp} <= time) {
      INFO('Access token has expired');
      $dbh->do('DELETE FROM oauth2_jwt WHERE id = ?',
        undef, $jwt_data->{id});
      return (0, 'invalid_grant');
    }
    elsif ($scopes_ref) {
      foreach my $scope (@{$scopes_ref // []}) {
        if (!_has_scope($scope, $jwt_claims->{scopes})) {
          INFO("Scope $scope not found");
          return (0, 'invalid_grant');
        }
      }
    }

    return ($jwt_claims, undef, $jwt_claims->{scopes}, $jwt_claims->{user_id});
  }
  else {
    INFO('Access token does not exist');
    return (0, 'invalid_grant');
  }
}

sub _get_jwt_claims {
  my ($jwt, $check_type) = @_;
  my ($claims, $jwt_error);

  try {
    $claims = Bugzilla->jwt->decode($jwt);
  }
  catch {
    INFO("Error decoding JWT: $_");
    $jwt_error = 1;
  };

  return (0) if $jwt_error;

  if (defined $check_type && $check_type ne $claims->{type}) {
    INFO("JWT not correct type: got: " . $claims->{type} . " expected: $check_type");
    return (0);
  }

  return (1, $claims);
}

sub _has_scope {
  my ($scope, $available_scopes) = @_;
  return any {$scope} @{$available_scopes // []};
}

1;
