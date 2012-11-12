#!/usr/bin/perl -wT
# This Source Code Form is subject to the terms of the Mozilla Public
# License,  v. 2.0. If a copy of the MPL was not distributed with this
# file,  You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses",  as
# defined by the Mozilla Public License,  v. 2.0.

use strict;

use lib '.';

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::User;
use Bugzilla::Field;
use Bugzilla::Util qw(trick_taint);

use Getopt::Long;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

my $field_name = "";
my $product    = "";
my $component  = "";
my $help       = "";
my %user_cache = ();

my $result = GetOptions('field=s' => \$field_name,
                        'product=s'   => \$product,
                        'component=s' => \$component,
                        'help|h'      => \$help);

sub usage {
    print <<USAGE;
Usage: reset_default_user.pl --field <fieldname> --product <product> [--component <component>] [--help]

This script will load all bugs matching the product, and optionally component,
and reset the default user value back to the default value for the component.
Valid field names are assigned_to and qa_contact.
USAGE
}

if (!$product || $help
    || ($field_name ne 'assigned_to' && $field_name ne 'qa_contact'))
{
    usage();
    exit(1);
}

# We will need these for entering into bugs_activity
my $who   = Bugzilla::User->new({ name => 'nobody@mozilla.org' });
my $field = Bugzilla::Field->new({ name => $field_name });

trick_taint($product);
my $product_id = $dbh->selectrow_array(
    "SELECT id FROM products WHERE name = ?",
    undef, $product);
$product_id or die "Can't find product ID for '$product'.\n";

my $component_id;
my $default_user_id;
if ($component) {
    trick_taint($component);
    my $colname = $field->name eq 'qa_contact'
                  ? 'initialqacontact'
                  : 'initialowner';
    ($component_id, $default_user_id) = $dbh->selectrow_array(
        "SELECT id, $colname FROM components " .
        "WHERE name = ? AND product_id = ?",
        undef, $component, $product_id);
    $component_id or die "Can't find component ID for '$component'.\n";
    $user_cache{$default_user_id} ||= Bugzilla::User->new($default_user_id);
}

# build list of bugs
my $bugs_query = "SELECT bug_id, qa_contact, component_id " .
                 "FROM bugs WHERE product_id = ?";
my @args = ($product_id);

if ($component_id) {
    $bugs_query .= " AND component_id = ? AND qa_contact != ?";
    push(@args, $component_id, $default_user_id);
}

my $bugs = $dbh->selectall_arrayref($bugs_query, {Slice => {}}, @args);
my $bug_count = scalar @$bugs;
$bug_count
    or die "No bugs were found.\n";

# confirmation
print <<EOF;
About to reset $field_name for $bug_count bugs.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

$dbh->bz_start_transaction();

foreach my $bug (@$bugs) {
    my $bug_id      = $bug->{bug_id};
    my $old_user_id = $bug->{$field->name};
    my $old_comp_id = $bug->{component_id};

    # If only changing one component, we already have the default user id
    my $new_user_id;
    if ($default_user_id) {
        $new_user_id = $default_user_id;
    }
    else {
        my $colname = $field->name eq 'qa_contact'
                      ? 'initialqacontact'
                      : 'initialowner';
        $new_user_id = $dbh->selectrow_array(
            "SELECT $colname FROM components WHERE id = ?",
            undef, $old_comp_id);
    }

    if ($old_user_id != $new_user_id) {
        print "Resetting " . $field->name . " for bug $bug_id ...";

        # Use the cached version if already exists
        my $old_user = $user_cache{$old_user_id} ||= Bugzilla::User->new($old_user_id);
        my $new_user = $user_cache{$new_user_id} ||= Bugzilla::User->new($new_user_id);

        my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

        $dbh->do("UPDATE bugs SET " . $field->name . " = ? WHERE bug_id = ?",
                 undef, $new_user_id, $bug_id);
        $dbh->do("INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) " .
                 "VALUES (?, ?, ?, ?, ?, ?)",
                 undef, $bug_id, $who->id, $timestamp, $field->id, $old_user->login, $new_user->login);
        $dbh->do("UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
                 undef, $timestamp, $timestamp, $bug_id);

        print "done.\n";
    }
}

$dbh->bz_commit_transaction();
