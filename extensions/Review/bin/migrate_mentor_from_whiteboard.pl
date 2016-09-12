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

my $mentor_field = Bugzilla::Field->check({ name => 'bug_mentor' });
my $dbh = Bugzilla->dbh;

# fix broken migration

my $sth = $dbh->prepare("
    SELECT id, bug_id, bug_when, removed, added
      FROM bugs_activity
     WHERE fieldid = ?
     ORDER BY bug_id,bug_when,removed
");
$sth->execute($mentor_field->id);
my %pair;
while (my $row = $sth->fetchrow_hashref) {
    if ($row->{added} && $row->{removed}) {
        %pair = ();
        next;
    }
    if ($row->{added}) {
        $pair{bug_id} = $row->{bug_id};
        $pair{bug_when} = $row->{bug_when};
        $pair{who} = $row->{added};
        next;
    }
    if (!$pair{bug_id}) {
        next;
    }
    if ($row->{removed}) {
        if ($row->{bug_id} == $pair{bug_id}
            && $row->{bug_when} eq $pair{bug_when}
            && $row->{removed} eq $pair{who})
        {
            print "Fixing mentor on bug $row->{bug_id}\n";
            my $user = Bugzilla::User->check({ name => $row->{removed} });
            $dbh->bz_start_transaction;
            $dbh->do(
                "DELETE FROM bugs_activity WHERE id = ?",
                undef,
                $row->{id}
            );
            my ($exists) = $dbh->selectrow_array(
                "SELECT 1 FROM bug_mentors WHERE bug_id = ? AND user_id = ?",
                undef,
                $row->{bug_id}, $user->id
            );
            if (!$exists) {
                $dbh->do(
                    "INSERT INTO bug_mentors (bug_id, user_id) VALUES (?, ?)",
                    undef,
                    $row->{bug_id}, $user->id,
                );
            }
            $dbh->bz_commit_transaction;
            %pair = ();
        }
    }
}

# migrate remaining bugs

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
    my $orig_whiteboard = $whiteboard;
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
    $dbh->do(
        "UPDATE bugs SET status_whiteboard=? WHERE bug_id=?",
        undef,
        $whiteboard, $bug->id
    );
    Bugzilla::Bug::LogActivityEntry(
        $bug->id,
        'status_whiteboard',
        $orig_whiteboard,
        $whiteboard,
        $nobody->id,
        $delta_ts,
    );
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
            my $user = Bugzilla::User->new({ name => $mentor_string });
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

sub find_users {
    my ($query) = @_;
    my $matches = Bugzilla::User::match("*$query*", 2);
    return [
        grep { $_->name =~ /:?\Q$query\E\b/i }
        @$matches
    ];
}
