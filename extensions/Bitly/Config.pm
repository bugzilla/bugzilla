# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Bitly;
use strict;

use Bugzilla::Install::Util qw(vers_cmp);

use constant NAME => 'Bitly';

sub REQUIRED_MODULES {
    my @required;
    push @required, {
        package => 'LWP',
        module  => 'LWP',
        version => 5,
    };
    # LWP 6 split https support into a separate package
    if (Bugzilla::Install::Requirements::have_vers({
        package => 'LWP',
        module  => 'LWP',
        version => 6,
    })) {
        push @required, {
            package => 'LWP-Protocol-https',
            module  => 'LWP::Protocol::https',
            version => 0
        };
    }
    return \@required;
}

use constant OPTIONAL_MODULES => [
    {
        package => 'Mozilla-CA',
        module  => 'Mozilla::CA',
        version => 0
    },
];

__PACKAGE__->NAME;
