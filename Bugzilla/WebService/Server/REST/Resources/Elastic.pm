# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::Server::REST::Resources::Elastic;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::WebService::Constants;
use Bugzilla::WebService::Elastic;

BEGIN {
  *Bugzilla::WebService::Elastic::rest_resources = \&_rest_resources;
}

sub _rest_resources {
  my $rest_resources
    = [qr{^/elastic/suggest_users$}, {GET => {method => 'suggest_users'},},];
  return $rest_resources;
}

1;
