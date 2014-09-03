#!/usr/bin/perl -w
use strict;

use Cwd 'abs_path';
use File::Basename;
use FindBin;
use lib "$FindBin::Bin/../..";
use lib "$FindBin::Bin/../../lib";

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::FlagType;
use Bugzilla::Hook;
use Bugzilla::Util;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 4) {
    die <<USAGE;
Usage: movebugs.pl <old-product> <old-component> <new-product> <new-component>

Eg. movebugs.pl mozilla.org bmo bugzilla.mozilla.org admin
Will move all bugs in the mozilla.org:bmo component to the
bugzilla.mozilla.org:admin component.

The new product must have matching versions, milestones, and flags from the old
product (will be validated by this script).
USAGE
}

my ($old_product, $old_component, $new_product, $new_component) = @ARGV;

my $dbh = Bugzilla->dbh;

my $old_product_id = $dbh->selectrow_array(
    "SELECT id FROM products WHERE name=?",
    undef, $old_product);
$old_product_id
    or die "Can't find product ID for '$old_product'.\n";

my $old_component_id = $dbh->selectrow_array(
    "SELECT id FROM components WHERE name=? AND product_id=?",
    undef, $old_component, $old_product_id);
$old_component_id
    or die "Can't find component ID for '$old_component'.\n";

my $new_product_id = $dbh->selectrow_array(
    "SELECT id FROM products WHERE name=?",
    undef, $new_product);
$new_product_id
    or die "Can't find product ID for '$new_product'.\n";

my $new_component_id = $dbh->selectrow_array(
    "SELECT id FROM components WHERE name=? AND product_id=?",
    undef, $new_component, $new_product_id);
$new_component_id
    or die "Can't find component ID for '$new_component'.\n";

my $product_field_id = $dbh->selectrow_array(
    "SELECT id FROM fielddefs WHERE name = 'product'");
$product_field_id
    or die "Can't find field ID for 'product' field\n";
my $component_field_id = $dbh->selectrow_array(
    "SELECT id FROM fielddefs WHERE name = 'component'");
$component_field_id
    or die "Can't find field ID for 'component' field\n";

my $user_id = $dbh->selectrow_array(
    "SELECT userid FROM profiles WHERE login_name='nobody\@mozilla.org'");
$user_id
    or die "Can't find user ID for 'nobody\@mozilla.org'\n";

$dbh->bz_start_transaction();

# build list of bugs
my $ra_ids = $dbh->selectcol_arrayref(
    "SELECT bug_id FROM bugs WHERE product_id=? AND component_id=?",
    undef, $old_product_id, $old_component_id);
my $bug_count = scalar @$ra_ids;
$bug_count
    or die "No bugs were found in '$old_component'\n";
my $where_sql = 'bug_id IN (' . join(',', @$ra_ids) . ')';

# check versions
my @missing_versions;
my $ra_versions = $dbh->selectcol_arrayref(
    "SELECT DISTINCT version FROM bugs WHERE $where_sql");
foreach my $version (@$ra_versions) {
    my $has_version = $dbh->selectrow_array(
        "SELECT 1 FROM versions WHERE product_id=? AND value=?",
        undef, $new_product_id, $version);
    push @missing_versions, $version unless $has_version;
}

# check milestones
my @missing_milestones;
my $ra_milestones = $dbh->selectcol_arrayref(
    "SELECT DISTINCT target_milestone FROM bugs WHERE $where_sql");
foreach my $milestone (@$ra_milestones) {
    my $has_milestone = $dbh->selectrow_array(
        "SELECT 1 FROM milestones WHERE product_id=? AND value=?",
        undef, $new_product_id, $milestone);
    push @missing_milestones, $milestone unless $has_milestone;
}

# check flags
my @missing_flags;
my $ra_old_types = $dbh->selectcol_arrayref(
    "SELECT DISTINCT type_id
       FROM flags
            INNER JOIN flagtypes ON flagtypes.id = flags.type_id
      WHERE $where_sql");
my $ra_new_types =
    Bugzilla::FlagType::match({ product_id   => $new_product_id,
                                component_id => $new_component_id });
foreach my $old_type (@$ra_old_types) {
    unless (grep { $_->id == $old_type } @$ra_new_types) {
        my $flagtype = Bugzilla::FlagType->new($old_type);
        push @missing_flags, $flagtype->name . ' (' . $flagtype->target_type . ')';
    }
}

# show missing
my $missing_error = '';
if (@missing_versions) {
    $missing_error .= "'$new_product' is missing the following version(s):\n  " .
        join("\n  ", @missing_versions) . "\n";
}
if (@missing_milestones) {
    $missing_error .= "'$new_product' is missing the following milestone(s):\n  " .
        join("\n  ", @missing_milestones) . "\n";
}
if (@missing_flags) {
    $missing_error .= "'$new_product'::'$new_component' is missing the following flag(s):\n  " .
        join("\n  ", @missing_flags) . "\n";
}
die $missing_error if $missing_error;

# confirmation
print <<EOF;
About to move $bug_count bugs
From '$old_product' : '$old_component'
To '$new_product' : '$new_component'

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

print "Moving $bug_count bugs from $old_product:$old_component to $new_product:$new_component\n";

# update bugs
$dbh->do(
    "UPDATE bugs SET product_id=?, component_id=? WHERE $where_sql",
    undef, $new_product_id, $new_component_id);

# touch bugs 
$dbh->do("UPDATE bugs SET delta_ts=NOW() WHERE $where_sql");
$dbh->do("UPDATE bugs SET lastdiffed=NOW() WHERE $where_sql");

# update bugs_activity
$dbh->do(
    "INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) 
          SELECT bug_id, ?, delta_ts, ?, ?, ?  FROM bugs WHERE $where_sql",
    undef,
    $user_id, $product_field_id, $old_product, $new_product);
$dbh->do(
    "INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) 
          SELECT bug_id, ?, delta_ts, ?, ?, ?  FROM bugs WHERE $where_sql",
    undef,
    $user_id, $component_field_id, $old_component, $new_component);

Bugzilla::Hook::process('reorg_move_bugs', { bug_ids => $ra_ids } );

$dbh->bz_commit_transaction();

foreach my $bug_id (@$ra_ids) {
    Bugzilla->memcached->clear({ table => 'bugs', id => $bug_id });
}

# It's complex to determine which items now need to be flushed from memcached.
# As this is expected to be a rare event, we just flush the entire cache.
Bugzilla->memcached->clear_all();
