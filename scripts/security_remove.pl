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
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::User;

use Pod::Usage;

# Load extensions for monkeypatched $user->clear_last_statistics_ts()
BEGIN { Bugzilla->extensions(); }

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 1) {
    die <<USAGE;
Usage: security_remove.pl <user>

E.g.: security_remove.pl foo\@bar.com

will remove the specified user from the following roles on private only bugs:

- Set reporter_accessible to false if user is the reporter
- Remove from the cc list
- Clear qa_contact if the user is qa_contact
- Re-assign to nobody\@mozilla.org if user is the assignee

This script should not touch user's membership or default assignee, qa contact,
or cc settings for components.

Script should not send any email about the changes.
USAGE
}

my ($login_name) = @ARGV;

# Load nobody user and set as current
my $auto_user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
Bugzilla->set_user($auto_user);

# Check target user
my $target_user = Bugzilla::User->check({ name => $login_name });

my $dbh = Bugzilla->dbh;
my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

# Gather bug ids
my $reporter_bugs = $dbh->selectcol_arrayref(
    q{SELECT DISTINCT bugs.bug_id
        FROM bugs, bug_group_map
       WHERE bugs.bug_id = bug_group_map.bug_id
             AND bugs.reporter_accessible = 1
             AND bugs.reporter = ?},
    undef, $target_user->id) || [];

my $assignee_bugs = $dbh->selectcol_arrayref(
    q{SELECT DISTINCT bugs.bug_id
        FROM bugs, bug_group_map
       WHERE bugs.bug_id = bug_group_map.bug_id
             AND bugs.assigned_to = ?},
    undef, $target_user->id) || [];

my $qa_bugs = $dbh->selectcol_arrayref(
    q{SELECT DISTINCT bugs.bug_id
        FROM bugs, bug_group_map
       WHERE bugs.bug_id = bug_group_map.bug_id
             AND bugs.qa_contact = ?},
    undef, $target_user->id) || [];

my $cc_bugs = $dbh->selectcol_arrayref(
    q{SELECT DISTINCT cc.bug_id
        FROM cc, bug_group_map
       WHERE cc.bug_id = bug_group_map.bug_id
             AND cc.who = ?},
    undef, $target_user->id) || [];

my $reporter_count = scalar @$reporter_bugs;
my $assignee_count = scalar @$assignee_bugs;
my $qa_count       = scalar @$qa_bugs;
my $cc_count       = scalar @$cc_bugs;

if (!$reporter_count
    && !$assignee_count
    && !$qa_count
    && !$cc_count)
{
    warn "There are no bugs to update.\n";
    exit 1;
}

warn <<EOF;
About to remove user from the following number of bugs:

Reporter:   $reporter_count
Assignee:   $assignee_count
QA Contact: $qa_count
CC:         $cc_count

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

$dbh->bz_start_transaction;

# Reporter - set reporter_accessible to false
my $field_id = get_field_id('reporter_accessible');
foreach my $bug_id (@$reporter_bugs) {
    warn "Updating bug $bug_id\n";
    $dbh->do(
        q{INSERT INTO bugs_activity (bug_id, who, bug_when, fieldid, removed, added)
         VALUES (?, ?, ?, ?, ?, ?)},
        undef, $bug_id, $auto_user->id, $timestamp, $field_id, 1, 0);
    $dbh->do(
        q{UPDATE bugs SET reporter_accessible = 0, delta_ts = ?, lastdiffed = ?
           WHERE bug_id = ?},
        undef, $timestamp, $timestamp, $bug_id);
}

# Assignee
$field_id = get_field_id('assigned_to');
foreach my $bug_id (@$assignee_bugs) {
    warn "Updating bug $bug_id\n";
    $dbh->do(
        q{INSERT INTO bugs_activity (bug_id, who, bug_when, fieldid, removed, added)
          VALUES (?, ?, ?, ?, ?, ?)},
        undef, $bug_id, $auto_user->id, $timestamp, $field_id,
               $target_user->login, $auto_user->login);
    $dbh->do(
        q{UPDATE bugs SET assigned_to = ?, delta_ts = ?, lastdiffed = ?
           WHERE bug_id = ?},
        undef, $auto_user->id, $timestamp, $timestamp, $bug_id);
}

# QA Contact
$field_id = get_field_id('qa_contact');
foreach my $bug_id (@$qa_bugs) {
    warn "Updating bug $bug_id\n";
    $dbh->do(
        q{INSERT INTO bugs_activity (bug_id, who, bug_when, fieldid, removed, added)
          VALUES (?, ?, ?, ?, ?, '')},
        undef, $bug_id, $auto_user->id, $timestamp, $field_id, $target_user->login);
    $dbh->do(
        q{UPDATE bugs SET qa_contact = NULL, delta_ts = ?, lastdiffed = ?
           WHERE bug_id = ?},
        undef, $timestamp, $timestamp, $bug_id);
}

# CC list
$field_id = get_field_id('cc');
foreach my $bug_id (@$cc_bugs) {
    warn "Updating bug $bug_id\n";
    $dbh->do(
        q{INSERT INTO bugs_activity (bug_id, who, bug_when, fieldid, removed, added)
          VALUES (?, ?, ?, ?, ?, '')},
        undef, $bug_id, $auto_user->id, $timestamp, $field_id, $target_user->login);
    $dbh->do(q{DELETE FROM cc WHERE bug_id = ? AND who = ?},
             undef, $bug_id, $target_user->id);
}

$target_user->clear_last_statistics_ts();

$dbh->bz_commit_transaction;

# It's complex to determine which items now need to be flushed from memcached.
# As this is expected to be a rare event, we just flush the entire cache.
Bugzilla->memcached->clear_all();

__END__

=head1 NAME

security_remove.pl - Remove user from any role associated with private bugs.

=head1 SYNOPSIS

    security_remove.pl foo@bar.com
