# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TrackingFlags::Constants;

use strict;
use base qw(Exporter);

our @EXPORT = qw(
    FLAG_TYPES
);

use constant FLAG_TYPES => [
    {
        name        => 'tracking',
        description => 'Tracking Flags',
        collapsed   => 1,
    },
    {
        name        => 'project',
        description => 'Project Flags',
        collapsed   => 0,
    },
    {
        name        => 'blocking',
        description => 'Blocking Flags',
        collapsed   => 1,
    },
    {
        name        => 'b2g',
        description => 'B2G Flags',
        collapsed   => 1,
    }
];

1;
