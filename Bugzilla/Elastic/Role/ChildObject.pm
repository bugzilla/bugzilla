# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Elastic::Role::ChildObject;

use 5.10.1;
use Role::Tiny;

with 'Bugzilla::Elastic::Role::Object';

requires qw(ES_PARENT_CLASS es_parent_id);

sub ES_PARENT_TYPE { $_[0]->ES_PARENT_CLASS->ES_TYPE }
sub ES_INDEX       { $_[0]->ES_PARENT_CLASS->ES_INDEX }
sub ES_SETTINGS    { $_[0]->ES_PARENT_CLASS->ES_SETTINGS }

1;
