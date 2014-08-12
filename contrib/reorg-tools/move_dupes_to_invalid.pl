#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use FindBin '$RealBin';
use lib "$RealBin/../..", "$RealBin/../../lib";

use Bugzilla;
use Bugzilla::User;
use Bugzilla::Constants;
use Bugzilla::Util qw(detaint_natural);
use Bugzilla::Install::Util qw(indicate_progress);

use Pod::Usage;

BEGIN { Bugzilla->extensions(); }

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

pod2usage(1) unless @ARGV;

my $dbh = Bugzilla->dbh;

# Allow nobody@mozilla.org to edit bugs
my $user = Bugzilla::User->check({ name => 'nobody@mozilla.org' });
Bugzilla->set_user($user);
$user->{'groups'} = [ Bugzilla::Group->new({ name => 'editbugs' }) ];

my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

foreach my $dupe_of_bug (@ARGV) {
    detaint_natural($dupe_of_bug) || pod2usage(1);
    my $duped_bugs = $dbh->selectcol_arrayref("
        SELECT DISTINCT dupe FROM duplicates WHERE dupe_of = ?",
        undef, $dupe_of_bug);
    my $bug_count = @$duped_bugs;

    die "There are no duplicate bugs to move for bug $dupe_of_bug.\n"
        if $bug_count == 0;

    print STDERR <<EOF;
Moving $bug_count duplicate bugs from bug $dupe_of_bug to the 'Invalid Bugs' product.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
    getc();

    $dbh->bz_start_transaction;
    my $count = 0;
    foreach my $duped_bug_id (@$duped_bugs) {
        # Change product to "Invalid Bugs" and component to "General"
        # Change resolution to "INVALID" instead of duplicate
        # Change version to "unspecified" and milestone to "---"
        # Reset assignee to default
        # Reset QA contact to default
        my $bug_obj = Bugzilla::Bug->new($duped_bug_id);
        my $params = {
            product           => 'Invalid Bugs',
            component         => 'General',
            resolution        => 'INVALID',
            version           => 'unspecified',
            target_milestone  => '---',
            reset_assigned_to => 1,
            reset_qa_contact  => 1
        };
        $params->{bug_status} = 'RESOLVED' if $bug_obj->status->is_open;
        $bug_obj->set_all($params);
        $bug_obj->update($timestamp);

        $dbh->do("UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
            undef, $timestamp, $timestamp, $duped_bug_id);

        $count++;
        indicate_progress({ current => $count, total => $bug_count, every => 1 });
    }

    Bugzilla::Hook::process('reorg_move_bugs', { bug_ids => [ $dupe_of_bug, @$duped_bugs ] });

    $dbh->bz_commit_transaction();
}

Bugzilla->memcached->clear_all();

__END__

=head1 NAME

move_dupes_to_invalid.pl - Script used to move dupes of a given bug to the 'Invalid Bugs' product.

=head1 SYNOPSIS

    move_dupes_to_invalid.pl <bug_id> [<bug_id> ...]
