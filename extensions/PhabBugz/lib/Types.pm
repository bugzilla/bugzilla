# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Types;

use 5.10.1;
use strict;
use warnings;

use Type::Library
    -base,
    -declare => qw( Revision PhabUser Policy Project );
use Type::Utils -all;
use Types::Standard -types;

class_type Revision, { class => 'Bugzilla::Extension::PhabBugz::Revision' };
class_type Policy, { class => 'Bugzilla::Extension::PhabBugz::Policy' };
class_type Project, { class => 'Bugzilla::Extension::PhabBugz::Project' };
class_type PhabUser, { class => 'Bugzilla::Extension::PhabBugz::User' };

1;
