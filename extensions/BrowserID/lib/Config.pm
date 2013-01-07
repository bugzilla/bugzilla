# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::BrowserID::Config;

use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 1350;

sub get_param_list {
    my ($class) = @_;

    my @param_list = (
        {
            name    => 'browserid_verify_url',
            type    => 't',
            default => 'https://browserid.org/verify',
        },
        {
            name    => 'browserid_includejs_url',
            type    => 't',
            default => 'https://browserid.org/include.js',
        }
    );

    return @param_list;
}

1;
