# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Error::Template;

use 5.10.1;
use strict;
use warnings;
use Moo;

has 'file' => (
    is       => 'ro',
    required => 1,
);

has 'vars' => (
    is      => 'ro',
    default => sub { {} },
);


1;