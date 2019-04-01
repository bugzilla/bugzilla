# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Model::Result::Flag;
use Mojo::Base 'DBIx::Class::Core';

__PACKAGE__->load_components('Helper::Row::NumifyGet');

__PACKAGE__->table(Bugzilla::Flag->DB_TABLE);
__PACKAGE__->add_columns(Bugzilla::Flag->DB_COLUMN_NAMES);

__PACKAGE__->add_columns(
  '+id'           => {is_numeric => 1},
  '+type_id'      => {is_numeric => 1},
  '+bug_id'       => {is_numeric => 1},
  '+attach_id'    => {is_numeric => 1},
  '+setter_id'    => {is_numeric => 1},
  '+requestee_id' => {is_numeric => 1},
);

__PACKAGE__->set_primary_key(Bugzilla::Flag->ID_FIELD);

__PACKAGE__->belongs_to(bug => 'Bugzilla::Model::Result::Bug', 'bug_id');
__PACKAGE__->belongs_to(type => 'Bugzilla::Model::Result::FlagType', 'type_id');
__PACKAGE__->has_one(
  setter => 'Bugzilla::Model::Result::User',
  {'foreign.userid' => 'self.setter_id'}
);

__PACKAGE__->might_have(
  requestee => 'Bugzilla::Model::Result::User',
  {'foreign.userid' => 'self.requestee_id'}
);


1;
