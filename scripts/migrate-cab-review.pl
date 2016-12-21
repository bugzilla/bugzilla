#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);




use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Group;
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::User;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

# Make all changes as the automation user
my $auto_user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
$auto_user->{groups} = [ Bugzilla::Group->get_all ];
$auto_user->{bless_groups} = [ Bugzilla::Group->get_all ];
Bugzilla->set_user($auto_user);

# cab-review flag values to custom field values mapping
my %map = (
    '?' => '?',
    '+' => 'approved',
    '-' => 'denied'
);

# Verify that all of the custom field values in the mapping data are present
my $cab_field = Bugzilla::Field->check({ name => 'cf_cab_review' });
foreach my $value (values %map) {
    unless (grep($_ eq $value, map { $_->name } @{ $cab_field->legal_values })) {
        die "Value '$value' does not exist. Please add to 'cf_cab_review.\n";
    }
}

# Grab list of bugs with cab-review flag set
my $sql = <<EOF;
    SELECT bugs.bug_id
      FROM bugs JOIN flags ON bugs.bug_id = flags.bug_id
           JOIN flagtypes ON flags.type_id = flagtypes.id
     WHERE flagtypes.name = 'cab-review' AND flags.status IN ('?','+', '-')
     ORDER BY bug_id
EOF

print "Searching for matching bugs..\n";
my $bugs = $dbh->selectcol_arrayref($sql);
my ($current, $total, $updated) = (1, scalar(@$bugs), 0);

die "No matching bugs found\n" unless $total;
print "About to update $total bugs with cab-review flags set and migrate to the cf_cab_review custom field.\n";
print "Press <enter> to start, or ^C to cancel...\n";
<>;

foreach my $bug_id (@$bugs) {
    indicate_progress({ current => $current++, total => $total, every => 5 });

    # Load bug object
    my $bug = Bugzilla::Bug->new($bug_id);

    # Find the current cab-review status
    my $cab_flag;
    foreach my $flag (@{ $bug->flags }) {
        next if $flag->type->name ne 'cab-review';
        $cab_flag = $flag;
        last;
    }

    my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

    $dbh->bz_start_transaction;

    # Set the cab-review custom field to the right status based on the mapped values
    $bug->set_custom_field($cab_field, $map{$cab_flag->status});

    # Clear the old cab-review flag
    $bug->set_flags([{ id => $cab_flag->id, status => 'X' }], []);

    # Update the bug
    $bug->update($timestamp);

    # Do not send email about this change
    $dbh->do("UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
        undef, $timestamp, $timestamp, $bug_id);

    $dbh->bz_commit_transaction;
    $updated++;
}

print "Bugs updated: $updated\n";
