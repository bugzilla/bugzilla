# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GoogleAnalytics;

use 5.10.1;
use strict;
use warnings;
use parent qw(Bugzilla::Extension);

our $VERSION = '0.1';

sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  $modules->{GoogleAnalytics} = "Bugzilla::Extension::GoogleAnalytics::Config";
}

__PACKAGE__->NAME;
