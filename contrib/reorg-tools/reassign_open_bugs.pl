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
use Bugzilla::User;
use Bugzilla::Constants;

use Getopt::Long qw( :config gnu_getopt );
use Pod::Usage;

# Load extensions for monkeypatched $user->clear_last_statistics_ts()
BEGIN { Bugzilla->extensions(); }

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($from, $to);
GetOptions(
    "from|f=s" => \$from,
    "to|t=s"   => \$to,
);

pod2usage(1) unless defined $from && defined $to;

my $dbh = Bugzilla->dbh;

my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
my $field     = Bugzilla::Field->check({ name => 'assigned_to', cache => 1 });
my $from_user = Bugzilla::User->check({ name => $from, cache => 1 });
my $to_user   = Bugzilla::User->check({ name => $to, cache => 1 });

my $bugs = $dbh->selectcol_arrayref(q{SELECT bug_id
                                      FROM bugs
                                      LEFT JOIN bug_status
                                             ON bug_status.value = bugs.bug_status
                                      WHERE bug_status.is_open = 1
                                        AND bugs.assigned_to = ?}, undef, $from_user->id);
my $bug_count = @$bugs;
if ($bug_count == 0) {
    warn "There are no bugs to move.\n";
    exit 1;
}

print STDERR <<EOF;
About to move $bug_count bugs from $from to $to.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

$dbh->bz_start_transaction;
foreach my $bug_id (@$bugs) {
    warn "Updating bug $bug_id\n";
    $dbh->do(q{INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added)
               VALUES (?, ?, ?, ?, ?, ?)},
                undef, $bug_id, $to_user->id, $timestamp, $field->id, $from_user->login, $to_user->login);
    $dbh->do(q{UPDATE bugs SET assigned_to = ?, delta_ts = ?, lastdiffed = ? WHERE bug_id = ?},
        undef, $to_user->id, $timestamp, $timestamp, $bug_id);
}
$from_user->clear_last_statistics_ts();
$to_user->clear_last_statistics_ts();
$dbh->bz_commit_transaction;

Bugzilla->memcached->clear_all();

__END__

=head1 NAME

reassign-open-bugs.pl - reassign all open bugs from one user to another.

=head1 SYNOPSIS

    reassign-open-bugs.pl --from general@js.bugs --to nobody@mozilla.org
