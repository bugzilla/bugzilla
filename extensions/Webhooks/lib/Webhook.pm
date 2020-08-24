# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Webhooks::Webhook;

use base qw(Bugzilla::Object);

use 5.10.1;
use strict;
use warnings;

use Bugzilla::User;
use Bugzilla::Product;
use Bugzilla::Component;
use Bugzilla::Error;

use constant DB_TABLE => 'webhooks';

use constant DB_COLUMNS => qw(
  id
  name
  url
  user_id
  event
  product_id
  component_id
);

use constant LIST_ORDER => 'id';

use constant UPDATE_COLUMNS => ();

use constant VALIDATORS => {
  user_id    => \&_check_user,
};
use constant VALIDATOR_DEPENDENCIES => {component_id => ['product_id'],};

use constant AUDIT_CREATES => 0;
use constant AUDIT_UPDATES => 0;
use constant AUDIT_REMOVES => 0;
use constant USE_MEMCACHED => 0;

# getters

sub user {
  my ($self) = @_;
  return Bugzilla::User->new({id => $self->{user_id}, cache => 1});
}

sub id {
  return $_[0]->{id};
}

sub name {
  return $_[0]->{name};
}

sub url {
  return $_[0]->{url};
}

sub event {
  return $_[0]->{event};
}

sub product_id {
  return $_[0]->{product_id};
}

sub component_id {
  return $_[0]->{component_id};
}

sub product {
  my ($self) = @_;
  return $self->{product} ||=
    Bugzilla::Product->new({id => $self->{product_id}, cache => 1});
}

sub product_name {
  my ($self) = @_;
  return $self->{product_name} ||= $self->{product_id} ? $self->product->name : '';
}

sub component {
  my ($self) = @_;
  return $self->{component} ||= $self->{component_id}
    ? Bugzilla::Component->new({id => $self->{component_id}, cache => 1}) : undef;
}

sub component_name {
  my ($self) = @_;
  return $self->{component_name} ||= $self->{component_id} ? $self->component->name : '';
}

# validators

sub _check_user {
  my ($class, $user) = @_;
  $user || ThrowCodeError('param_required', {param => 'user'});
}

1;
