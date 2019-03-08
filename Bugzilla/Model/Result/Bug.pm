# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Model::Result::Bug;
use Mojo::Base 'DBIx::Class::Core';

__PACKAGE__->table(Bugzilla::Bug->DB_TABLE);
__PACKAGE__->add_columns(Bugzilla::Bug->DB_COLUMN_NAMES);
__PACKAGE__->set_primary_key(Bugzilla::Bug->ID_FIELD);

__PACKAGE__->has_one(
  reporter => 'Bugzilla::Model::Result::User',
  {'foreign.userid' => 'self.reporter'}
);

__PACKAGE__->has_one(
  assigned_to => 'Bugzilla::Model::Result::User',
  {'foreign.userid' => 'self.assigned_to'}
);
__PACKAGE__->might_have(
  qa_contact => 'Bugzilla::Model::Result::User',
  {'foreign.userid' => 'self.qa_contact'}
);

__PACKAGE__->has_many(
  bug_keywords => 'Bugzilla::Model::Result::BugKeyword',
  'bug_id'
);

__PACKAGE__->many_to_many(keywords => 'bug_keywords', 'keyword');

__PACKAGE__->has_many(flags => 'Bugzilla::Model::Result::Flag', 'bug_id');

__PACKAGE__->has_many(
  bug_groups => 'Bugzilla::Model::Result::BugGroup',
  'bug_id'
);
__PACKAGE__->many_to_many(groups => 'bug_groups', 'group');

__PACKAGE__->has_one(
  product => 'Bugzilla::Model::Result::Product',
  {'foreign.id' => 'self.product_id'}
);

__PACKAGE__->has_one(
  component => 'Bugzilla::Model::Result::Component',
  {'foreign.id' => 'self.component_id'}
);


1;

