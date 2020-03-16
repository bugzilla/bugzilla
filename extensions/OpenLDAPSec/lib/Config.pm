# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::OpenLDAPSec::Config;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;
use Bugzilla::Constants;

our $sortkey = 5000;

sub get_param_list {
    my ($class) = @_;

    my @params = (
        {
            name    => 'public_list',
            type    => 's',
            choices => \&_get_disabled_users,
            default => '',
            checker => \&_check_disabled_user
        },
        {
            name    => 'insider_list',
            type    => 's',
            choices => \&_get_disabled_insiders,
            default => '',
            checker => \&_check_insider_user
        },
    );

    return @params;
}

sub _get_disabled_users {
    my $search = Bugzilla::Object::match('Bugzilla::User', {is_enabled => 0});
    my @user_names = map { $_->login } @$search;
    unshift(@user_names, '');
    return \@user_names;
}

sub _check_disabled_user {
    my $login = shift;
    return "" unless $login;
    my $user = new Bugzilla::User({'name' => $login});
    unless (defined $user) {
        return "Must be an existing user name";
    }
    unless ($user->disabledtext) {
        return "Must be a disabled user";
    }
    return "";
}

sub _get_disabled_insiders {
    my $search = Bugzilla::Object::match('Bugzilla::User', {is_enabled => 0});
    my @user_names = map { $_->login } grep { $_->is_insider } @$search;
    unshift(@user_names, '');
    return \@user_names;
}

sub _check_insider_user {
    my $login = shift;
    return "" unless $login;
    my $user = new Bugzilla::User({'name' => $login});
    unless (defined $user) {
        return "Must be an existing user name";
    }
    unless ($user->disabledtext && $user->is_insider) {
        return "Must be a disabled member of the insiders group";
    }
    return "";
}

1;
