# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Gravatar;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::User::Setting;
use Digest::MD5 qw(md5_hex);

BEGIN {
    *Bugzilla::User::gravatar = \&_user_gravatar;
}

sub _user_gravatar {
    my ($self) = @_;
    if (!$self->{gravatar}) {
        (my $email = $self->email) =~ s/\+(.*?)\@/@/;
        $self->{gravatar} = 'https://secure.gravatar.com/avatar/' . md5_hex(lc($email)) . "?size=32&d=mm";
    }
    return $self->{gravatar};
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    add_setting('show_gravatars', ['On', 'Off'], 'Off');
}

__PACKAGE__->NAME;
