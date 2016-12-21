#!/usr/bin/perl -w

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
use Bugzilla::Constants;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

$dbh->bz_start_transaction();
my $attachment_sizes = $dbh->selectall_arrayref(q{
        SELECT attachments.attach_id, length(thedata)
        FROM attach_data
        INNER JOIN attachments ON attachments.attach_id = attach_data.id
        WHERE attachments.attach_size != 0
          AND attachments.mimetype = 'image/png'
          AND length(thedata) != attachments.attach_size });
say "Found ", scalar @$attachment_sizes, " attachments to fix";

foreach my $attachment_size (@$attachment_sizes) {
    say "Setting size for $attachment_size->[0] to $attachment_size->[1]";

    $dbh->do("UPDATE attachments SET attach_size = ? WHERE attach_id = ?", undef,
             $attachment_size->[1],
             $attachment_size->[0]);
}

$dbh->bz_commit_transaction();