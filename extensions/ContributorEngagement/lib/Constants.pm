# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ContributorEngagement::Constants;

use strict;

use base qw(Exporter);

our @EXPORT = qw(
    EMAIL_FROM
    ENABLED_PRODUCTS
    FLAG_REGEXES 
);

use constant EMAIL_FROM => 'bugzilla-daemon@mozilla.org';

use constant ENABLED_PRODUCTS => (
    "Core",
    "Firefox for Android", 
    "Firefox",
    "Testing", 
    "Toolkit", 
    "Mozilla Services", 
    "TestProduct", 
);

use constant FLAG_REGEXES => (
    qr/^approval/
);

1;
