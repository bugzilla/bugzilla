# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Model::Result::Bug;
use Mojo::Base 'DBIx::Class::Core';

__PACKAGE__->load_components('Helper::Row::NumifyGet');

__PACKAGE__->table(Bugzilla::Bug->DB_TABLE);
__PACKAGE__->add_columns(Bugzilla::Bug->DB_COLUMN_NAMES);
__PACKAGE__->add_columns(
  '+bug_id'   => {is_numeric => 1},
  '+reporter' => {is_numeric => 1}
  '+qa_contact' => {is_numeric => 1}
  '+assigned_to' => {is_numeric => 1}
);
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
  map_keywords => 'Bugzilla::Model::Result::BugKeyword',
  'bug_id'
);

__PACKAGE__->many_to_many(keywords => 'map_keywords', 'keyword');

__PACKAGE__->has_many(flags => 'Bugzilla::Model::Result::Flag', 'bug_id');

__PACKAGE__->has_many(
  map_groups => 'Bugzilla::Model::Result::BugGroup',
  'bug_id'
);
__PACKAGE__->many_to_many(groups => 'map_groups', 'group');

__PACKAGE__->has_many(
  map_depends_on => 'Bugzilla::Model::Result::Dependency',
  'dependson'
);
__PACKAGE__->many_to_many(depends_on => 'map_depends_on', 'depends_on');

__PACKAGE__->has_many(
  map_blocked_by => 'Bugzilla::Model::Result::Dependency',
  'blocked'
);
__PACKAGE__->many_to_many(blocked_by => 'map_depends_on', 'blocked_by');

__PACKAGE__->has_one(
  product => 'Bugzilla::Model::Result::Product',
  {'foreign.id' => 'self.product_id'}
);

__PACKAGE__->has_one(
  component => 'Bugzilla::Model::Result::Component',
  {'foreign.id' => 'self.component_id'}
);


__PACKAGE__->has_many(
  map_duplicates => 'Bugzilla::Model::Result::Duplicate',
  'dupe_of'
);

__PACKAGE__->many_to_many('duplicates', 'map_duplicates', 'duplicate');

__PACKAGE__->might_have( map_duplicate_of => 'Bugzilla::Model::Result::Duplicate', 'dupe');

sub duplicate_of {
  my ($self) = @_;

  my $duplicate = $self->map_duplicate_of;
  return $duplicate->duplicate_of if $duplicate;
  return undef;
}

1;

