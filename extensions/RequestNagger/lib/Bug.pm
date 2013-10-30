# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::RequestNagger::Bug;

use strict;
use parent qw(Bugzilla::Bug);

sub short_desc {
    my ($self) = @_;
    return $self->{secure_bug} ? '(Secure bug)' : $self->SUPER::short_desc;
}

sub tooltip {
    my ($self) = @_;
    my $tooltip = $self->bug_status;
    if ($self->bug_status eq 'RESOLVED') {
        $tooltip .= '/' . $self->resolution;
    }
    if (!$self->{secure_bug}) {
        $tooltip .= ' ' . $self->product . ' :: ' . $self->component;
    }
    return $tooltip;
}

1;
