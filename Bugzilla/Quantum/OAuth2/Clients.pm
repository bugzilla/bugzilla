# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::OAuth2::Clients;
use Mojo::Base 'Mojolicious::Controller';

use 5.10.1;
use List::Util qw(first);
use Moo;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Token;
use Bugzilla::Util qw(generate_random_password);

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
    return $self->render(template => 'admin/oauth/create',
      handler => 'bugzilla');
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


  $dbh->do(
    'INSERT INTO oauth2_client (id, description, secret) VALUES (?, ?, ?)',
    undef, $id, $description, $secret);

  foreach my $scope_id (@scopes) {
    $scope_id
      = $dbh->selectrow_array('SELECT id FROM oauth2_scope WHERE id = ?',
      undef, $scope_id);
    if (!$scope_id) {
      ThrowCodeError('param_required', {param => 'scopes'});
    }
    $dbh->do(
      'INSERT INTO oauth2_client_scope (client_id, scope_id, allowed) VALUES (?, ?, 1)',
      undef, $id, $scope_id
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

  my $id = $self->param('id');
  my $client
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE id = ?',
    undef, $id);

  if (!$self->param('deleteme')) {
    $vars->{'client'} = $client;
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
  $vars->{'client'}  = {description => $client->{description}};
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

  my $client
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE id = ?',
    undef, $id);
  my $client_scopes
    = $dbh->selectall_arrayref(
    'SELECT scope_id FROM oauth2_client_scope WHERE client_id = ?',
    undef, $id);
  $client->{scopes} = [map { $_->[0] } @{$client_scopes}];
  $vars->{client} = $client;

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

  if ($description ne $client->{description}) {
    $dbh->do('UPDATE oauth2_client SET description = ? WHERE id = ?',
      undef, $description, $id);
  }

  if ($active ne $client->{active}) {
    $dbh->do('UPDATE oauth2_client SET active = ? WHERE id = ?',
      undef, $active, $id);
  }

  $dbh->do('DELETE FROM oauth2_client_scope WHERE client_id = ?', undef, $id);
  foreach my $scope_id (@scopes) {
    $dbh->do(
      'INSERT INTO oauth2_client_scope (client_id, scope_id, allowed) VALUES (?, ?, 1)',
      undef, $id, $scope_id
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
