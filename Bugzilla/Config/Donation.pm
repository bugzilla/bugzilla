# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::Donation;

use 5.14.0;
use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 175;

use constant get_param_list => (
  {
    name    => 'donation_banner_visibility',
    type    => 's',
    choices => ['admins_only', 'end_users', 'disabled'],
    default => 'admins_only',
    checker => \&check_multi,
  },
);

1;

__END__

=head1 NAME

Bugzilla::Config::Donation - Donation banner settings

=cut