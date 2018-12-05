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
use Digest::MD5 qw(md5_hex);

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
  return $self->{gravatar} . '&amp;size=' . $size;
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

__PACKAGE__->NAME;
