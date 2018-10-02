# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Error::Base;

use 5.10.1;
use Mojo::Base 'Mojo::Exception';

has 'vars' => sub { {} };

has 'template' => sub {
    my $self = shift;
    my $type = lc( (split(/::/, ref $self))[-1] );
    return "global/$type-error";
};

1;
