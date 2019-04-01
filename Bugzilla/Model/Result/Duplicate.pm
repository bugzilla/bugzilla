# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Model::Result::Duplicate;
use Mojo::Base 'DBIx::Class::Core';

__PACKAGE__->table('duplicates');
__PACKAGE__->add_columns(qw[ dupe_of dupe ]);
__PACKAGE__->set_primary_key(qw[ dupe ]);

__PACKAGE__->belongs_to(
  duplicate => 'Bugzilla::Model::Result::Bug',
  {'foreign.bug_id' => 'self.dupe'}
);

__PACKAGE__->belongs_to(
  duplicate_of => 'Bugzilla::Model::Result::Bug',
  {'foreign.bug_id' => 'self.dupe_of'}
);

1;
