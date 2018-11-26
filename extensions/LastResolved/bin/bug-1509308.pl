#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Field;

my $dbh = Bugzilla->dbh;
my $resolved_activity = $dbh->selectall_arrayref(
  'SELECT id, bug_id, bug_when FROM bugs_activity WHERE fieldid = ? ORDER BY bug_when',
  undef, get_field_id('cf_last_resolved'));
my %last_resolved;

foreach my $activity (@$resolved_activity) {
  my ($id, $bug_id, $added) = @$activity;
  my $removed = $last_resolved{$bug_id} || '';

  # Copy the `bug_when` column to `added` so it will be UTC instead of PST
  $dbh->do('UPDATE bugs_activity SET added = ?, removed = ? WHERE id = ?',
    undef, $added, $removed, $id);

  # Cache the timestamp as a bug can be resolved multiple times
  $last_resolved{$bug_id} = $added;
}
