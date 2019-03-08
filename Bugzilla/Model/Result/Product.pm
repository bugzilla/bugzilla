# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Model::Result::Product;
use Mojo::Base 'DBIx::Class::Core';

__PACKAGE__->table(Bugzilla::Product->DB_TABLE);
__PACKAGE__->add_columns(Bugzilla::Product->DB_COLUMN_NAMES);
__PACKAGE__->set_primary_key(Bugzilla::Product->ID_FIELD);

__PACKAGE__->has_many('components', 'Bugzilla::Model::Result::Component', 'product_id');

1;
