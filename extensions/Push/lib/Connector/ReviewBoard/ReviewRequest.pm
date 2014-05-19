# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::ReviewBoard::ReviewRequest;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::ReviewBoard::Resource';

# Reference: http://www.reviewboard.org/docs/manual/dev/webapi/2.0/resources/review-request/

sub path {
    return '/api/review-requests';
}

sub delete {
    my ($self, $id) = @_;

    return $self->client->useragent->delete($self->uri($id));
}

1;
