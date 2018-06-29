# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::Advanced;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;
use Bugzilla::Util qw(validate_ip);

our $sortkey = 1700;

use constant get_param_list => (
    {
        name    => 'proxy_url',
        type    => 't',
        default => ''
    },

    {
        name    => 'strict_transport_security',
        type    => 's',
        choices => [ 'off', 'this_domain_only', 'include_subdomains' ],
        default => 'off',
        checker => \&check_multi
    },

    {
        name    => 'disable_bug_updates',
        type    => 'b',
        default => 0
    },
);

1;
