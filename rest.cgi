#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
BEGIN {
    if (!Bugzilla->feature('rest')) {
        ThrowUserError('feature_disabled', { feature => 'rest' });
    }
}
Bugzilla->usage_mode(USAGE_MODE_REST);
Bugzilla->api_server->handle();
