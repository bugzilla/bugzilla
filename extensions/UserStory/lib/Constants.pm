# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::UserStory::Constants;

use strict;
use warnings;

use base qw(Exporter);

our @EXPORT = qw( USER_STORY_PRODUCTS );

use constant USER_STORY_PRODUCTS => {
    # product   group required to edit
    Tracking    => 'editbugs',
};

1;
