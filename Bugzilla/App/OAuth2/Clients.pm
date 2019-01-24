# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::OAuth2::Clients;
use 5.10.1;
use Mojo::Base 'Mojolicious::Controller';

use List::Util qw(first);
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Token;
use Bugzilla::Util qw(generate_random_password);

sub setup_routes {
  my ($class, $r) = @_;

  # Manage the client list
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
}

# Show list of clients
sub list {
  my ($self) = @_;
  my $clients = Bugzilla->dbh->selectall_arrayref('SELECT * FROM oauth2_client',
    {Slice => {}});
  $self->stash(clients => $clients);
  return $self->render(template => 'admin/oauth/list', handler => 'bugzilla');
}

# Create new client
sub create {
  my ($self) = @_;
  my $dbh    = Bugzilla->dbh;
  my $vars   = {};

  if ($self->req->method ne 'POST') {
    $vars->{id}     = generate_random_password(20);
    $vars->{secret} = generate_random_password(40);
    $vars->{token}  = issue_session_token('create_oauth_client');
    $vars->{scopes}
      = $dbh->selectall_arrayref('SELECT * FROM oauth2_scope', {Slice => {}});
    $self->stash(%{$vars});
    return $self->render(template => 'admin/oauth/create', handler => 'bugzilla');
  }

  $dbh->bz_start_transaction;

  my $description = $self->param('description');
  my $id          = $self->param('id');
  my $secret      = $self->param('secret');
  my @scopes      = $self->param('scopes');
  $description || ThrowCodeError('param_required', {param => 'description'});
  $id          || ThrowCodeError('param_required', {param => 'id'});
  $secret      || ThrowCodeError('param_required', {param => 'secret'});
  @scopes      || ThrowCodeError('param_required', {param => 'scopes'});
  my $token = $self->param('token');
  check_token_data($token, 'create_oauth_client');


  $dbh->do('INSERT INTO oauth2_client (client_id, description, secret) VALUES (?, ?, ?)',
    undef, $id, $description, $secret);

  my $client_data
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE client_id = ?',
    undef, $id);

  foreach my $scope_id (@scopes) {
    $scope_id = $dbh->selectrow_array('SELECT id FROM oauth2_scope WHERE id = ?',
      undef, $scope_id);
    if (!$scope_id) {
      ThrowCodeError('param_required', {param => 'scopes'});
    }
    $dbh->do(
      'INSERT INTO oauth2_client_scope (client_id, scope_id) VALUES (?, ?)',
      undef, $client_data->{id}, $scope_id
    );
  }

  delete_token($token);

  my $clients
    = $dbh->selectall_arrayref('SELECT * FROM oauth2_client', {Slice => {}});

  $dbh->bz_commit_transaction;

  $vars->{'message'} = 'oauth_client_created';
  $vars->{'client'}  = {description => $description};
  $vars->{'clients'} = $clients;
  $self->stash(%{$vars});
  return $self->render(template => 'admin/oauth/list', handler => 'bugzilla');
}

# Delete client
sub delete {
  my ($self) = @_;
  my $dbh    = Bugzilla->dbh;
  my $vars   = {};

  my $id          = $self->param('id');
  my $client_data = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE id = ?',
    undef, $id);

  if (!$self->param('deleteme')) {
    $vars->{'client'} = $client_data;
    $vars->{'token'}  = issue_session_token('delete_oauth_client');
    $self->stash(%{$vars});
    return $self->render(
      template => 'admin/oauth/confirm-delete',
      handler  => 'bugzilla'
    );
  }

  $dbh->bz_start_transaction;

  my $token = $self->param('token');
  check_token_data($token, 'delete_oauth_client');

  $dbh->do('DELETE FROM oauth2_client WHERE id = ?', undef, $id);

  delete_token($token);

  my $clients
    = $dbh->selectall_arrayref('SELECT * FROM oauth2_client', {Slice => {}});

  $dbh->bz_commit_transaction;

  $vars->{'message'} = 'oauth_client_deleted';
  $vars->{'client'}  = {description => $client_data->{description}};
  $vars->{'clients'} = $clients;
  $self->stash(%{$vars});
  return $self->render(template => 'admin/oauth/list', handler => 'bugzilla');
}

#  Edit client
sub edit {
  my ($self) = @_;
  my $dbh    = Bugzilla->dbh;
  my $vars   = {};
  my $id     = $self->param('id');

  my $client_data = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE id = ?',
    undef, $id);
  my $client_scopes
    = $dbh->selectall_arrayref(
    'SELECT scope_id FROM oauth2_client_scope WHERE client_id = ?',
    undef, $client_data->{id});
  $client_data->{scopes} = [map { $_->[0] } @{$client_scopes}];
  $vars->{client} = $client_data;

  # All scopes
  my $all_scopes
    = $dbh->selectall_arrayref('SELECT * FROM oauth2_scope', {Slice => {}});
  $vars->{scopes} = $all_scopes;

  if ($self->req->method ne 'POST') {
    $vars->{token} = issue_session_token('edit_oauth_client');
    $self->stash(%{$vars});
    return $self->render(template => 'admin/oauth/edit', handler => 'bugzilla');
  }

  $dbh->bz_start_transaction;

  my $token = $self->param('token');
  check_token_data($token, 'edit_oauth_client');

  my $description = $self->param('description');
  my $active      = $self->param('active');
  my @scopes      = $self->param('scopes');

  if ($description ne $client_data->{description}) {
    $dbh->do('UPDATE oauth2_client SET description = ? WHERE id = ?',
      undef, $description, $id);
  }

  if ($active ne $client_data->{active}) {
    $dbh->do('UPDATE oauth2_client SET active = ? WHERE id = ?',
      undef, $active, $id);
  }

  $dbh->do('DELETE FROM oauth2_client_scope WHERE client_id = ?', undef, $id);
  foreach my $scope_id (@scopes) {
    $dbh->do(
      'INSERT INTO oauth2_client_scope (client_id, scope_id) VALUES (?, ?)',
      undef, $client_data->{id}, $scope_id
    );
  }

  delete_token($token);

  my $clients
    = $dbh->selectall_arrayref('SELECT * FROM oauth2_client', {Slice => {}});

  $dbh->bz_commit_transaction;

  $vars->{'message'} = 'oauth_client_updated';
  $vars->{'client'}  = {description => $description};
  $vars->{'clients'} = $clients;
  $self->stash(%{$vars});
  return $self->render(template => 'admin/oauth/list', handler => 'bugzilla');
}

1;
