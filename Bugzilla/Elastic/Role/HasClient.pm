# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Elastic::Role::HasClient;

use 5.10.1;
use Moo::Role;
use Search::Elasticsearch;


has 'client' => (is => 'lazy');

sub _build_client {
    my ($self) = @_;

    return Search::Elasticsearch->new(
        nodes => Bugzilla->params->{elasticsearch_nodes},
        cxn_pool => 'Sniff',
    );
}

1;
