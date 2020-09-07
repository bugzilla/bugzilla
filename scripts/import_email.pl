#!/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Import email messages from a mbox file and place in jobqueue

use 5.10.1;
use strict;
use warnings;
use lib qw(/app /app/local/lib/perl5);

use Bugzilla;

my $filename = shift;
die "Need mbox filename\n" if !$filename;

print "Processing $filename\n";

open my $fh, '<:encoding(UTF-8)', $filename || die "Could not open mbox file: $!\n";

my ($msg, $count);
while (my $line = <$fh>) {
  if ($line =~ /^From - /) {
    if ($msg) {
      Bugzilla->job_queue->insert('send_mail', {msg => $msg});
      $count++;
    }
    $msg = undef;
    next;
  }
  $msg .= $line;
}

close $fh || die "Could not close mbox file: $!\n";

print "Imported $count emails\n";
