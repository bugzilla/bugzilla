# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Types;

use 5.10.1;
use strict;
use warnings;

use Type::Library
    -base,
    -declare => qw( Bug User Group Attachment Comment JSONBool );
use Type::Utils -all;
use Types::Standard -types;

class_type Bug,        { class => 'Bugzilla::Bug' };
class_type User,       { class => 'Bugzilla::User' };
class_type Group,      { class => 'Bugzilla::Group' };
class_type Attachment, { class => 'Bugzilla::Attachment' };
class_type Comment,    { class => 'Bugzilla::Comment' };
class_type JSONBool,   { class => 'JSON::PP::Boolean' };

1;
