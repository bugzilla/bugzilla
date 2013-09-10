# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Ember;

use 5.10.1;
use strict;
use parent qw(Bugzilla::Extension);

our $VERSION = '0.01';

sub webservice {
    my ($self,  $args) = @_;
    my $dispatch = $args->{dispatch};
    $dispatch->{Ember} = "Bugzilla::Extension::Ember::WebService";
}

__PACKAGE__->NAME;
