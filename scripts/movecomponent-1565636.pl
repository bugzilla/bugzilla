#!/usr/bin/env perl
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
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Hook;
use Bugzilla::Product;
use Bugzilla::Util;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

if (scalar @ARGV < 3) {
  die <<"USAGE";
Usage: movecomponent.pl <oldproduct> <newproduct> <component>

E.g.: movecomponent.pl ReplicationEngine FoodReplicator SeaMonkey
will move the component "SeaMonkey" from the product "ReplicationEngine"
to the product "FoodReplicator".

Important: You must make sure the milestones and versions of the bugs in the
component are available in the new product. See syncmsandversions.pl.

USAGE
}

use constant VERSION_MAP => {
  'Firefox 22' => '22 Branch',
  'Firefox 23' => '23 Branch',
  'Firefox 24' => '24 Branch',
  'Firefox 25' => '25 Branch',
  'Firefox 26' => '26 Branch',
  'Firefox 27' => '27 Branch',
  'Firefox 28' => '28 Branch',
  'Firefox 29' => '29 Branch',
  'Firefox 30' => '30 Branch',
  'Firefox 31' => '31 Branch',
  'Firefox 32' => '32 Branch',
  'Firefox 33' => '33 Branch',
  'Firefox 34' => '34 Branch',
  'Firefox 35' => '35 Branch',
  'Firefox 36' => '36 Branch',
  'Firefox 37' => '37 Branch',
  'Firefox 38' => '38 Branch',
  'Firefox 39' => '39 Branch',
  'Firefox 40' => '40 Branch',
  'Firefox 41' => '41 Branch',
  'Firefox 42' => '42 Branch',
  'Firefox 43' => '43 Branch',
  'Firefox 44' => '44 Branch',
  'Firefox 45' => '45 Branch',
  'Firefox 46' => '46 Branch',
  'Firefox 47' => '47 Branch',
  'Firefox 48' => '48 Branch',
  'Firefox 49' => '49 Branch',
  'Firefox 50' => '50 Branch',
  'Firefox 51' => '51 Branch',
  'Firefox 52' => '52 Branch',
  'Firefox 53' => '53 Branch',
  'Firefox 54' => '54 Branch',
  'Firefox 55' => '55 Branch',
  'Firefox 56' => '56 Branch',
  'Firefox 57' => '57 Branch',
  'Firefox 58' => '58 Branch',
  'Firefox 59' => '59 Branch',
  'Firefox 60' => '60 Branch',
  'Firefox 61' => '61 Branch',
  'Firefox 62' => '62 Branch',
  'Firefox 63' => '63 Branch',
  'Firefox 64' => '64 Branch',
  'Firefox 65' => '65 Branch',
  'Firefox 66' => '66 Branch',
  'Firefox 67' => '67 Branch',
  'Firefox 68' => '68 Branch',
  'Firefox 69' => '69 Branch',
  'Firefox 70' => '70 Branch'
};

use constant MILESTONE_MAP => {
  'Firefox 11' => 'mozilla11',
  'Firefox 12' => 'mozilla12',
  'Firefox 13' => 'mozilla13',
  'Firefox 14' => 'mozilla14',
  'Firefox 15' => 'mozilla15',
  'Firefox 16' => 'mozilla16',
  'Firefox 17' => 'mozilla17',
  'Firefox 18' => 'mozilla18',
  'Firefox 19' => 'mozilla19',
  'Firefox 20' => 'mozilla20',
  'Firefox 21' => 'mozilla21',
  'Firefox 22' => 'mozilla22',
  'Firefox 23' => 'mozilla23',
  'Firefox 24' => 'mozilla24',
  'Firefox 25' => 'mozilla25',
  'Firefox 26' => 'mozilla26',
  'Firefox 27' => 'mozilla27',
  'Firefox 28' => 'mozilla28',
  'Firefox 29' => 'mozilla29',
  'Firefox 30' => 'mozilla30',
  'Firefox 31' => 'mozilla31',
  'Firefox 32' => 'mozilla32',
  'Firefox 33' => 'mozilla33',
  'Firefox 34' => 'mozilla34',
  'Firefox 35' => 'mozilla35',
  'Firefox 36' => 'mozilla36',
  'Firefox 37' => 'mozilla37',
  'Firefox 38' => 'mozilla38',
  'Firefox 39' => 'mozilla39',
  'Firefox 40' => 'mozilla40',
  'Firefox 41' => 'mozilla41',
  'Firefox 42' => 'mozilla42',
  'Firefox 43' => 'mozilla43',
  'Firefox 44' => 'mozilla44',
  'Firefox 45' => 'mozilla45',
  'Firefox 46' => 'mozilla46',
  'Firefox 47' => 'mozilla47',
  'Firefox 48' => 'mozilla48',
  'Firefox 49' => 'mozilla49',
  'Firefox 50' => 'mozilla50',
  'Firefox 51' => 'mozilla51',
  'Firefox 52' => 'mozilla52',
  'Firefox 53' => 'mozilla53',
  'Firefox 54' => 'mozilla54',
  'Firefox 55' => 'mozilla55',
  'Firefox 56' => 'mozilla56',
  'Firefox 57' => 'mozilla57',
  'Firefox 58' => 'mozilla58',
  'Firefox 59' => 'mozilla59',
  'Firefox 60' => 'mozilla60',
  'Firefox 61' => 'mozilla61',
  'Firefox 62' => 'mozilla62',
  'Firefox 63' => 'mozilla63',
  'Firefox 64' => 'mozilla64',
  'Firefox 65' => 'mozilla65',
  'Firefox 66' => 'mozilla66',
  'Firefox 67' => 'mozilla67',
  'Firefox 68' => 'mozilla68',
  'Firefox 69' => 'mozilla69',
  'Firefox 70' => 'mozilla70',
};

my ($old_product_name, $new_product_name, $component_name) = @ARGV;
my $old_product = Bugzilla::Product->check({name => $old_product_name});
my $new_product = Bugzilla::Product->check({name => $new_product_name});
my $component   = Bugzilla::Component->check(
  {product => $old_product, name => $component_name});

my $product_field_id   = get_field_id('product');
my $version_field_id   = get_field_id('version');
my $milestone_field_id = get_field_id('target_milestone');

my $dbh = Bugzilla->dbh;

# confirmation
print <<"EOF";
About to move the component '$component_name'
From '$old_product_name'
To '$new_product_name'

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc;

print
  "Moving '$component_name' from '$old_product_name' to '$new_product_name'...\n\n";
$dbh->bz_start_transaction();

my $auto_user = Bugzilla::User->check({name => 'automation@bmo.tld'});
Bugzilla->set_user($auto_user);

my $bugs = $dbh->selectall_arrayref(
  'SELECT bug_id, version, target_milestone FROM bugs WHERE product_id = ? AND component_id = ?',
  {Slice => {}}, $old_product->id, $component->id
);

foreach my $bug (@$bugs) {

  # Update product in bugs table
  $dbh->do('UPDATE bugs SET product_id = ? WHERE component_id = ? AND bug_id = ?',
    undef, $new_product->id, $component->id, $bug->{bug_id});

  # Update bugs_activity for product change
  $dbh->do(
    'INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) VALUES (?, ?, NOW(), ?, ?, ?)',
    undef,
    $bug->{bug_id},
    $auto_user->id,
    $product_field_id,
    $old_product_name,
    $new_product_name
  );

  # Update version if necessary
  if (VERSION_MAP()->{$bug->{version}}) {

    # Update version in bugs table
    $dbh->do(
      'UPDATE bugs SET version = ? WHERE bug_id = ?',
      undef, VERSION_MAP()->{$bug->{version}},
      $bug->{bug_id}
    );

    # Update bugs_activity for version change
    $dbh->do(
      'INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) VALUES (?, ?, NOW(), ?, ?, ?)',
      undef,
      $bug->{bug_id},
      $auto_user->id,
      $version_field_id,
      $bug->{version},
      VERSION_MAP()->{$bug->{version}}
    );
  }

  # Update milestone if necessary
  if (MILESTONE_MAP()->{$bug->{target_milestone}}) {

    # Update target_milestone in bugs table
    $dbh->do(
      'UPDATE bugs SET target_milestone = ? WHERE bug_id = ?', undef,
      MILESTONE_MAP()->{$bug->{target_milestone}},             $bug->{bug_id}
    );

    # Update bugs_activity for milestone change
    $dbh->do(
      'INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added) VALUES (?, ?, NOW(), ?, ?, ?)',
      undef,
      $bug->{bug_id},
      $auto_user->id,
      $milestone_field_id,
      $bug->{target_milestone},
      MILESTONE_MAP()->{$bug->{target_milestone}}
    );
  }

  # Mark bug as touched
  $dbh->do(
    'UPDATE bugs SET delta_ts = NOW(), lastdiffed = NOW() WHERE bug_id = ?',
    undef, $bug->{bug_id});

  print 'Bug ' . $bug->{bug_id} . "\n";
}

# Flags tables
fix_flags('flaginclusions', $new_product, $component);
fix_flags('flagexclusions', $new_product, $component);

# Components
$dbh->do('UPDATE components SET product_id = ? WHERE id = ?',
  undef, ($new_product->id, $component->id));

Bugzilla::Hook::process(
  'reorg_move_component',
  {
    old_product => $old_product,
    new_product => $new_product,
    component   => $component,
  }
);

Bugzilla::Hook::process('reorg_move_bugs',
  {bug_ids => [map { $_->{bug_id} } @$bugs]});

$dbh->bz_commit_transaction();

# It's complex to determine which items now need to be flushed from memcached.
# As this is expected to be a rare event, we just flush the entire cache.
Bugzilla->memcached->clear_all();

sub fix_flags {
  my ($table, $new_product_obj, $component_obj) = @_;
  my $type_ids
    = $dbh->selectcol_arrayref(
    "SELECT DISTINCT type_id FROM $table WHERE component_id = ?",
    undef, $component_obj->id);
  $dbh->do(
    'DELETE FROM ' . $dbh->quote_identifier($table) . ' WHERE component_id = ?',
    undef, $component_obj->id);
  foreach my $type_id (@$type_ids) {
    $dbh->do(
      'INSERT INTO '
        . $dbh->quote_identifier($table)
        . ' (type_id, product_id, component_id) VALUES (?, ?, ?)',
      undef,
      ($type_id, $new_product_obj->id, $component_obj->id)
    );
  }
}
