# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::1_0::Resource::Example;

use 5.10.1;
use strict;
use warnings;
use parent qw(Bugzilla::API::1_0::Resource);
use Bugzilla::Error;

#############
# Constants #
#############

use constant READ_ONLY => qw(
    hello
    throw_an_error
);

use constant PUBLIC_METHODS => qw(
    hello
    throw_an_error
);

sub REST_RESOURCES {
    my $rest_resources = [
        qr{^/hello$}, {
            GET  => {
                method => 'hello'
            }
        },
        qr{^/throw_an_error$}, {
            GET => {
                method => 'throw_an_error'
            }
        }
    ];
    return $rest_resources;
}

###########
# Methods #
###########

# This can be called as Example.hello() from the WebService.
sub hello {
    return {
        message => 'Hello!'
    };
}

sub throw_an_error { ThrowUserError('example_my_error') }

1;
