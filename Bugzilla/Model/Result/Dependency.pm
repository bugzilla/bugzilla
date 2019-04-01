# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Model::Result::Dependency;
use Mojo::Base 'DBIx::Class::Core';

__PACKAGE__->load_components('Helper::Row::NumifyGet');

__PACKAGE__->table('dependencies');
__PACKAGE__->add_columns(qw[ blocked dependson ]);
__PACKAGE__->set_primary_key(qw[ blocked dependson ]);

__PACKAGE__->add_columns(
  '+blocked'   => {is_numeric => 1},
  '+dependson' => {is_numeric => 1},
);

__PACKAGE__->belongs_to(
  blocked_by => 'Bugzilla::Model::Result::Bug',
  {'foreign.bug_id' => 'self.blocked'}
);

__PACKAGE__->belongs_to(
  depends_on => 'Bugzilla::Model::Result::Bug',
  {'foreign.bug_id' => 'self.dependson'}
);


1;
