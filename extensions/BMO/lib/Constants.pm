# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Constants;

use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(
    REQUEST_MAX_ATTACH_LINES
    DEV_ENGAGE_DISCUSS_NEEDINFO
);

# Maximum attachment size in lines that will be sent with a 
# requested attachment flag notification.
use constant REQUEST_MAX_ATTACH_LINES => 1000;

# Requestees who need a needinfo flag set for the dev engagement
# discussion bug
use constant DEV_ENGAGE_DISCUSS_NEEDINFO => qw(
    spersing@mozilla.com
);

1;
