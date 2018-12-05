# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugModal::Util;

use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT_OK = qw(date_str_to_time);

use feature 'state';

use Bugzilla::Util qw(datetime_from);
use DateTime::TimeZone;
use Time::Local qw(timelocal);

sub date_str_to_time {
  my ($date) = @_;

  # avoid creating a DateTime object
  if ($date =~ /^(\d{4})[\.\-](\d{2})[\.\-](\d{2}) (\d{2}):(\d{2}):(\d{2})$/) {
    return timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900);
  }
  state $tz //= DateTime::TimeZone->new(name => 'local');
  my $dt = datetime_from($date, $tz);
  if (!$dt) {

    # this should never happen
    warn("invalid datetime '$date'");
    return undef;
  }
  return $dt->epoch;
}

1;
