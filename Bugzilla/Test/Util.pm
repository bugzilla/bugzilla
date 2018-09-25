# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Test::Util;

use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(create_user issue_api_key);

use Bugzilla::User;
use Bugzilla::User::APIKey;

sub create_user {
    my ($login, $password, %extra) = @_;
    require Bugzilla;
    return Bugzilla::User->create({
        login_name    => $login,
        cryptpassword => $password,
        disabledtext  => "",
        disable_mail  => 0,
        extern_id     => undef,
        %extra,
    });
}

sub issue_api_key {
    my ($login, $given_api_key) = @_;
    my $user = Bugzilla::User->check({ name => $login });

    my $params = {
        user_id     => $user->id,
        description => 'Bugzilla::Test::Util::issue_api_key',
        api_key     => $given_api_key,
    };

    if ($given_api_key) {
        return Bugzilla::User::APIKey->create_special($params);
    } else {
        return Bugzilla::User::APIKey->create($params);
    }
}

1;
