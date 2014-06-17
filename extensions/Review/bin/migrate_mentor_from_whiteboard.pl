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
$| = 1;

use FindBin qw($RealBin);
use lib "$RealBin/../../..";

use Bugzilla;
BEGIN { Bugzilla->extensions() }

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::User;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

print <<EOF;
This script migrates mentors from the whiteboard to BMO's bug_mentor field.
The mentor needs to be in the form of [mentor=UUU].

It's safe to run this script multiple times, or to cancel this script while
running.

Press <Return> to start, or Ctrl+C to cancel..
EOF
<>;

# we need to be logged in to do user searching and update bugs
my $nobody = Bugzilla::User->check({ name => 'nobody@mozilla.org' });
$nobody->{groups} = [ Bugzilla::Group->get_all ];
Bugzilla->set_user($nobody);

my $dbh = Bugzilla->dbh;
my $bug_ids = $dbh->selectcol_arrayref("
    SELECT bug_id
      FROM bugs
     WHERE status_whiteboard LIKE '%[mentor=%'
           AND resolution=''
     ORDER BY bug_id
");
print "Bugs found: " . scalar(@$bug_ids) . "\n";
my $bugs = Bugzilla::Bug->new_from_list($bug_ids);
foreach my $bug (@$bugs) {
    my $whiteboard = $bug->status_whiteboard;
    my ($mentors, $errors) = extract_mentors($whiteboard);

    printf "%7s %s\n", $bug->id, $whiteboard;
    foreach my $error (@$errors) {
        print "        $error\n";
    }
    foreach my $user (@$mentors) {
        print "        Mentor: " . $user->identity . "\n";
    }
    next if @$errors;
    $whiteboard =~ s/\[mentor=[^\]]+\]//g;

    my $migrated = $dbh->selectcol_arrayref(
        "SELECT user_id FROM bug_mentors WHERE bug_id = ?",
        undef,
        $bug->id
    );
    if (@$migrated) {
        foreach my $migrated_id (@$migrated) {
            $mentors = [
                grep { $_->id != $migrated_id }
                @$mentors
            ];
        }
        if (!@$mentors) {
            print "        mentor(s) already migrated\n";
            next;
        }
    }

    my $delta_ts = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    $dbh->bz_start_transaction;
    $bug->set_all({ status_whiteboard => $whiteboard });
    foreach my $mentor (@$mentors) {
        $dbh->do(
            "INSERT INTO bug_mentors (bug_id, user_id) VALUES (?, ?)",
            undef,
            $bug->id, $mentor->id,
        );
        Bugzilla::Bug::LogActivityEntry(
            $bug->id,
            'bug_mentor',
            '',
            $mentor->login,
            $nobody->id,
            $delta_ts,
        );
    }
    $bug->update($delta_ts);
    $dbh->do(
        "UPDATE bugs SET lastdiffed = delta_ts WHERE bug_id = ?",
        undef,
        $bug->id,
    );
    $dbh->bz_commit_transaction;
}

sub extract_mentors {
    my ($whiteboard) = @_;

    my (@mentors, @errors);
    my $logout = 0;
    while ($whiteboard =~ /\[mentor=([^\]]+)\]/g) {
        my $mentor_string = $1;
        $mentor_string =~ s/(^\s+|\s+$)//g;
        if ($mentor_string =~ /\@/) {
            # assume it's a full username if it contains an @
            my $user = Bugzilla::User->new({ name => $mentor_string, cache => 1 });
            if (!$user) {
                push @errors, "'$mentor_string' failed to match any users";
            } else {
                push @mentors, $user;
            }
        } else {
            # otherwise assume it's a : prefixed nick

            $mentor_string =~ s/^://;
            my $matches = find_users(":$mentor_string");
            if (!@$matches) {
                $matches = find_users($mentor_string);
            }

            if (!$matches || !@$matches) {
                push @errors, "'$mentor_string' failed to match any users";
            } elsif (scalar(@$matches) > 1) {
                push @errors, "'$mentor_string' matches more than one user: " .
                    join(', ', map { $_->identity } @$matches);
            } else {
                push @mentors, $matches->[0];
            }
        }
    }
    return (\@mentors, \@errors);
}

my %cache;

sub find_users {
    my ($query) = @_;
    if (!exists $cache{$query}) {
        my $matches = Bugzilla::User::match("*$query*", 2);
        $cache{$query} = [
            grep { $_->name =~ /:?\Q$query\E\b/i }
            @$matches
        ];
    }
    return $cache{$query};
}
