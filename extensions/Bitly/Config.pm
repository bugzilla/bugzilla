# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Bitly;
use strict;

use constant NAME => 'Bitly';
use constant REQUIRED_MODULES => [
    {
        package => 'LWP-Protocol-https',
        module  => 'LWP::Protocol::https',
        version => 0
    },
];
use constant OPTIONAL_MODULES => [
    {
        package => 'Mozilla-CA',
        module  => 'Mozilla::CA',
        version => 0
    },
];

__PACKAGE__->NAME;
