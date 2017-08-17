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
our @EXPORT = qw(create_user);

use Bugzilla::User;

sub create_user {
    my ($login, $password, %extra) = @_;
    require Bugzilla;
    return Bugzilla::User->create({
        login_name    => $login,
        cryptpassword => $password,
        disabledtext  => "",
        disable_mail  => 0,
        extern_id     => 0,
        %extra,
    });
}

1;
