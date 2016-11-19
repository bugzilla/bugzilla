# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Elastic::Role::HasIndexName;

use 5.10.1;
use Moo::Role;
use Search::Elasticsearch;

has 'index_name' => ( is => 'ro', default => sub { Bugzilla->params->{elasticsearch_index} } );


1;
