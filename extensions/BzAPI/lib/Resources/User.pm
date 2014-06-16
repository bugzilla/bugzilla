# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BzAPI::Resources::User;

use 5.10.1;
use strict;

use Bugzilla::Extension::BzAPI::Util;

sub rest_handlers {
    my $rest_handlers = [
        qr{/user$}, {
            GET  => {
                response => \&get_users,
            },
        },
        qr{/user/([^/]+)$}, {
            GET => {
                response => \&get_user,
            },
        }
    ];
    return $rest_handlers;
}

sub get_users {
    my ($result) = @_;
    my $rpc    = Bugzilla->request_cache->{bzapi_rpc};
    my $params = Bugzilla->input_params;

    return if !exists $$result->{users};

    my @users;
    foreach my $user (@{$$result->{users}}) {
        my $object = Bugzilla::User->new(
            { id => $user->{id}, cache => 1 });

        $user = fix_user($user, $object);

        # Use userid instead of email for 'ref' for /user calls
        $user->{'ref'} = $rpc->type('string', ref_urlbase . "/user/" . $object->id);

        # Emails are not filtered even if user is not logged in
        $user->{name} = $rpc->type('string', $object->login);

        push(@users, filter($params, $user));
    }

    $$result->{users} = \@users;
}

sub get_user {
    my ($result) = @_;
    my $rpc    = Bugzilla->request_cache->{bzapi_rpc};
    my $params = Bugzilla->input_params;

    return if !exists $$result->{users};
    my $user = $$result->{users}->[0] || return;
    my $object = Bugzilla::User->new({ id => $user->{id}, cache => 1 });

    $user = fix_user($user, $object);

    # Use userid instead of email for 'ref' for /user calls
    $user->{'ref'} = $rpc->type('string', ref_urlbase . "/user/" . $object->id);

    # Emails are not filtered even if user is not logged in
    $user->{name} = $rpc->type('string', $object->login);

    $user = filter($params, $user);

    $$result = $user;
}

1;
