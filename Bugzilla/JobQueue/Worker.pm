# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::JobQueue::Worker;
use 5.10.1;
use strict;
use warnings;

use Bugzilla::Logging;
use Module::Runtime qw(require_module);

sub run {
  my ($class, $fn) = @_;
  DEBUG("Starting up for $fn");
  my $jq = Bugzilla->job_queue();

  DEBUG('Loading jobqueue modules');
  foreach my $module (values %{Bugzilla::JobQueue->job_map()}) {
    DEBUG("JobQueue can do $module");
    require_module($module);
    $jq->can_do($module);
  }
  $jq->$fn;
}

1;
