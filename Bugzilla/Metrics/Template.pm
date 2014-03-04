# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Metrics::Template;

use strict;
use warnings;

use parent 'Bugzilla::Template';

sub process {
    my $self = shift;
    Bugzilla->metrics->template_start($_[0]);
    my $result = $self->SUPER::process(@_);
    Bugzilla->metrics->end();
    return $result;
}

1;
