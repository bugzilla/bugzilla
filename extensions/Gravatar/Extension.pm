# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Gravatar;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Extension::Gravatar::Data qw( %gravatar_user_map );
use Bugzilla::User::Setting;
use Bugzilla::WebService::Util qw(filter_wants);
use Digest::MD5 qw(md5_hex);
use Scalar::Util qw(blessed);

use constant DEFAULT_URL => 'extensions/Gravatar/web/default.jpg';

BEGIN {
  *Bugzilla::User::gravatar = \&_user_gravatar;
}

sub _user_gravatar {
  my ($self, $size) = @_;
  if ($self->setting('show_my_gravatar') eq 'Off') {
    return DEFAULT_URL;
  }
  if (!$self->{gravatar}) {
    my $email = $self->email;
    $email = $gravatar_user_map{$self->email}
      if exists $gravatar_user_map{$self->email};
    $self->{gravatar}
      = 'https://secure.gravatar.com/avatar/' . md5_hex(lc($email)) . '?d=mm';
  }
  $size ||= 64;
  return $self->{gravatar} . '&size=' . $size;
}

sub install_before_final_checks {
  my ($self, $args) = @_;
  add_setting({
    name     => 'show_gravatars',
    options  => ['On', 'Off'],
    default  => 'Off',
    category => 'Bug Editing'
  });
  add_setting({
    name     => 'show_my_gravatar',
    options  => ['On', 'Off'],
    default  => 'On',
    category => 'Bug Editing'
  });
}

#
# hooks
#

sub webservice_user_get {
  my ($self, $args) = @_;
  my ($webservice, $params, $users) = @$args{qw(webservice params users)};

  return unless filter_wants($params, 'gravatar');

  my $ids = [
    map { blessed($_->{id}) ? $_->{id}->value : $_->{id} }
    grep { exists $_->{id} }
    @$users
  ];

  return unless @$ids;

  my %user_map = map { $_->id => $_ } @{ Bugzilla::User->new_from_list($ids) };
  foreach my $user (@$users) {
    my $id = blessed($user->{id}) ? $user->{id}->value : $user->{id};
    my $user_obj = $user_map{$id};
    $user->{gravatar} = $user_obj->gravatar;
  }
}

sub webservice_user_suggest {
  my ($self, $args) = @_;
  $self->webservice_user_get($args);
}

__PACKAGE__->NAME;
