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

use FindBin '$RealBin';
use lib "$RealBin/../..", "$RealBin/../../lib";

use Bugzilla;
use Bugzilla::Field;
use Bugzilla::Constants;

use Getopt::Long qw( :config gnu_getopt );
use Pod::Usage;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($from_os, $to_os);
GetOptions('from=s' => \$from_os, 'to=s' => \$to_os);

pod2usage(1) unless defined $from_os && defined $to_os;


my $check_from_os = Bugzilla::Field::Choice->type('op_sys')->match({ value => $from_os });
my $check_to_os   = Bugzilla::Field::Choice->type('op_sys')->match({ value => $to_os });
die "Cannot move $from_os because it does not exist\n"
    unless @$check_from_os == 1;
die "Cannot move $from_os because $to_os doesn't exist.\n"
    unless @$check_to_os == 1;

my $dbh       = Bugzilla->dbh;
my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
my $bug_ids   = $dbh->selectcol_arrayref(q{SELECT bug_id FROM bugs WHERE bugs.op_sys = ?}, undef, $from_os);
my $field     = Bugzilla::Field->check({ name => 'op_sys', cache => 1 });
my $nobody    = Bugzilla::User->check({ name => 'nobody@mozilla.org', cache => 1 });

my $bug_count = @$bug_ids;
if ($bug_count == 0) {
    warn "There are no bugs to move.\n";
    exit 1;
}

print STDERR <<EOF;
About to move $bug_count bugs from $from_os to $to_os.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

$dbh->bz_start_transaction;
foreach my $bug_id (@$bug_ids) {
    warn "Moving $bug_id...\n";

    $dbh->do(q{INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added)
               VALUES (?, ?, ?, ?, ?, ?)},
                undef, $bug_id, $nobody->id, $timestamp, $field->id, $from_os, $to_os);
    $dbh->do(q{UPDATE bugs SET op_sys = ?, delta_ts = ?, lastdiffed = ? WHERE bug_id = ?},
        undef, $to_os, $timestamp, $timestamp, $bug_id);
}
$dbh->bz_commit_transaction;


Bugzilla->memcached->clear_all();

__END__

=head1 NAME

move_os.pl - move the os on all bugs with a particular os to a new os

=head1 SYNOPSIS

    move_os.pl --from 'Windows 8 Metro' --to 'Windows 8.1'
