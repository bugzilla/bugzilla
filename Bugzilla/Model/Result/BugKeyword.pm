# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Model::Result::BugKeyword;
use Mojo::Base 'DBIx::Class::Core';

__PACKAGE__->table('keywords');
__PACKAGE__->add_columns('bug_id', 'keywordid');
__PACKAGE__->set_primary_key('bug_id', 'keywordid');

__PACKAGE__->belongs_to(bug     => 'Bugzilla::Model::Result::Bug',     'bug_id');
__PACKAGE__->belongs_to(keyword => 'Bugzilla::Model::Result::Keyword', 'keywordid');

1;
