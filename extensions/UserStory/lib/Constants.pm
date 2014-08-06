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

our @EXPORT = qw( USER_STORY_EXCLUDE USER_STORY_GROUP );

# Group allowed to set/edit the user story field
use constant USER_STORY_GROUP => 'editbugs';

# Exclude showing the user story field for these products/components.
# Examples:
# Don't show User Story on any Firefox OS component:
#   'Firefox OS' => [],
# Don't show User Story on Developer Tools component, visible on all other
# Firefox components
#   'Firefox'    => ['Developer Tools'],
use constant USER_STORY_EXCLUDE => { };

1;
