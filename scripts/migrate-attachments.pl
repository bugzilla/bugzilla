#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/..", "$RealBin/../lib";

use Bugzilla;
use Bugzilla::Attachment;
use Bugzilla::Install::Util qw(indicate_progress);
use Getopt::Long qw(GetOptions);

my @storage_names = Bugzilla::Attachment->get_storage_names();

my %options;
GetOptions(\%options, 'mirror=s@{2}', 'delete=s') or exit(1);
unless ($options{mirror} || $options{delete}) {
    die <<EOF;
Syntax:
    migrate-attachments.pl --mirror source destination
    migrate-attachments.pl --delete source

'mirror'
    Copies all attachments from the specified source to the destination.
    Attachments which already exist at the destination will not be copied
    again.  Attachments deleted on the source will be deleted from the
    destination.

'delete'
    Deletes all attachments in the specified location.  This operation cannot
    be undone.

Valid locations:
    @storage_names

EOF
}

my $dbh = Bugzilla->dbh;
my ($total) = $dbh->selectrow_array("SELECT COUNT(*) FROM attachments");

if ($options{mirror}) {
    if ($options{mirror}->[0] eq $options{mirror}->[1]) {
        die "Source and destination must be different\n";
    }
    my ($source, $dest) = map { storage($_) } @{ $options{mirror} };
    confirm(sprintf('Mirror %s attachments from %s to %s?', $total, @{ $options{mirror} }));

    my $sth = $dbh->prepare("SELECT attach_id, attach_size FROM attachments ORDER BY attach_id");
    $sth->execute();
    my ($count, $deleted, $stored) = (0, 0, 0);
    while (my ($attach_id, $attach_size) = $sth->fetchrow_array()) {
        indicate_progress({ total => $total, current => ++$count });

        # remove deleted attachments
        if ($attach_size == 0 && $dest->exists($attach_id)) {
            $dest->remove($attach_id);
            $deleted++;
        }

        # store attachments that don't already exist
        elsif ($attach_size != 0 && !$dest->exists($attach_id)) {
            if (my $data = $source->retrieve($attach_id)) {
                $dest->store($attach_id, $data);
                $stored++;
            }
        }
    }
    print "\n";
    print "Attachments stored: $stored\n";
    print "Attachments deleted: $deleted\n" if $deleted;
}

elsif ($options{delete}) {
    my $storage = storage($options{delete});
    confirm(sprintf('DELETE %s attachments from %s?', $total, $options{delete}));

    my $sth = $dbh->prepare("SELECT attach_id FROM attachments ORDER BY attach_id");
    $sth->execute();
    my ($count, $deleted) = (0, 0);
    while (my ($attach_id) = $sth->fetchrow_array()) {
        indicate_progress({ total => $total, current => ++$count });
        if ($storage->exists($attach_id)) {
            $storage->remove($attach_id);
            $deleted++;
        }
    }
    print "\n";
    print "Attachments deleted: $deleted\n";
}

sub storage {
    my ($name) = @_;
    my $storage = Bugzilla::Attachment::get_storage_by_name($name)
        or die "Invalid attachment location: $name\n";
    return $storage;
}

sub confirm {
    my ($prompt) = @_;
    print $prompt, "\n\nPress <Ctrl-C> to stop or <Enter> to continue..\n";
    getc();
}
