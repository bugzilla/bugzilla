#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# -*- Mode: perl; indent-tabs-mode: nil -*-

use strict;
use warnings;

use File::Basename;
use File::Spec;

BEGIN {
  require lib;
  my $dir
    = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), "..", ".."));
  lib->import(
    $dir,
    File::Spec->catdir($dir, "lib"),
    File::Spec->catdir($dir, qw(local lib perl5))
  );
}

use Cwd;
use File::Copy::Recursive qw(dircopy);

my $conf_path;
my $config;

BEGIN {
  print "reading the config file...\n";
  my $conf_file = $ENV{BZ_QA_CONF_FILE} // "selenium_test.conf";
  if (@ARGV) {
    $conf_file = shift @ARGV;
  }
  $config = do "$conf_file" or die "can't read configuration '$conf_file': $!$@";

  $conf_path = $config->{bugzilla_path};
}

use lib $conf_path;

use Bugzilla;
use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::User;
use Bugzilla::Install;
use Bugzilla::Milestone;
use Bugzilla::Product;
use Bugzilla::Component;
use Bugzilla::Group;
use Bugzilla::Version;
use Bugzilla::Constants;
use Bugzilla::Keyword;
use Bugzilla::Config qw(:admin);
use Bugzilla::User::Setting;
use Bugzilla::Util qw(generate_random_password);

my $dbh = Bugzilla->dbh;

# set Bugzilla usage mode to USAGE_MODE_CMDLINE
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

##########################################################################
# Set Parameters
##########################################################################

# Create missing priorities
# BMO uses P1-P5 which is different from upstream
my $field = Bugzilla::Field->new({name => 'priority'});
foreach my $value (qw(Highest High Normal Low Lowest)) {
  Bugzilla::Field::Choice->type($field)->create({value => $value, sortkey => 0});
}

# Add missing platforms
$field = Bugzilla::Field->new({name => 'rep_platform'});
foreach my $value (qw(PC)) {
  Bugzilla::Field::Choice->type($field)->create({value => $value, sortkey => 0});
}

my %set_params = (
  usebugaliases              => 1,
  useqacontact               => 1,
  mail_delivery_method       => 'Test',
  maxattachmentsize          => 256,
  defaultpriority            => 'Highest',     # BMO CHANGE
  timetrackinggroup          => 'editbugs',    # BMO CHANGE
  letsubmitterchoosepriority => 1,             # BMO CHANGE
  createemailregexp          => '.*',          # BMO CHANGE
);

my $params_modified;
foreach my $param (keys %set_params) {
  my $value = $set_params{$param};
  next unless defined $value && Bugzilla->params->{$param} ne $value;
  SetParam($param, $value);
  $params_modified = 1;
}

write_params() if $params_modified;

##########################################################################
# Set Default User Preferences
##########################################################################

# When editing a bug, the page being displayed depends on the
# post_bug_submit_action user pref. We set it globally so that we know
# the exact behavior of process_bug.cgi.
my %user_prefs = (post_bug_submit_action => 'nothing');

foreach my $pref (keys %user_prefs) {
  my $value = $user_prefs{$pref};
  Bugzilla::User::Setting::set_default($pref, $value, 1);
}

##########################################################################
# Create Users
##########################################################################
# First of all, remove the default .* regexp for the editbugs group.
my $group = new Bugzilla::Group({name => 'editbugs'});
$group->set_user_regexp('');
$group->update();

my @usernames = (
  'admin',       'no-privs',       'QA-Selenium-TEST', 'canconfirm',
  'tweakparams', 'permanent_user', 'editbugs',         'disabled',
);

print "creating user accounts...\n";
foreach my $username (@usernames) {

  my $password;
  my $login;
  my $realname
    = exists $config->{"$username" . "_user_username"}
    ? $config->{"$username" . "_user_username"}
    : $username;

  if ($username eq 'permanent_user') {
    $password = $config->{admin_user_passwd};
    $login    = $config->{$username};
  }
  elsif ($username eq 'no-privs') {
    $password = $config->{unprivileged_user_passwd};
    $login    = $config->{unprivileged_user_login};
  }
  elsif ($username eq 'QA-Selenium-TEST') {
    $password = $config->{QA_Selenium_TEST_user_passwd};
    $login    = $config->{QA_Selenium_TEST_user_login};
  }
  else {
    $password = $config->{"$username" . "_user_passwd"};
    $login    = $config->{"$username" . "_user_login"};
  }

  if (is_available_username($login)) {
    my %extra_args;
    if ($username eq 'disabled') {
      $extra_args{disabledtext} = '!!This is the text!!';
    }

    Bugzilla::User->create({
      login_name    => $login,
      realname      => $realname,
      cryptpassword => $password,
      %extra_args,
    });

    if ($username eq 'admin' or $username eq 'permanent_user') {

      Bugzilla::Install::make_admin($login);
    }
  }
}

##########################################################################
# Bug statuses
##########################################################################

# We need to add in the upstream statuses in addition to the BMO ones.

my @statuses = (
  {
    value       => undef,
    transitions => [
      ['UNCONFIRMED', 0],
      ['CONFIRMED',   0],
      ['NEW',         0],
      ['ASSIGNED',    0],
      ['IN_PROGRESS', 0]
    ],
  },
  {
    value       => 'UNCONFIRMED',
    sortkey     => 100,
    isactive    => 1,
    isopen      => 1,
    transitions => [
      ['CONFIRMED',   0],
      ['NEW',         0],
      ['ASSIGNED',    0],
      ['IN_PROGRESS', 0],
      ['RESOLVED',    0]
    ],
  },
  {
    value       => 'CONFIRMED',
    sortkey     => 200,
    isactive    => 1,
    isopen      => 1,
    transitions => [
      ['UNCONFIRMED', 0],
      ['NEW',         0],
      ['ASSIGNED',    0],
      ['IN_PROGRESS', 0],
      ['RESOLVED',    0]
    ],
  },
  {
    value       => 'NEW',
    sortkey     => 300,
    isactive    => 1,
    isopen      => 1,
    transitions => [
      ['UNCONFIRMED', 0],
      ['CONFIRMED',   0],
      ['ASSIGNED',    0],
      ['IN_PROGRESS', 0],
      ['RESOLVED',    0]
    ],
  },
  {
    value       => 'ASSIGNED',
    sortkey     => 400,
    isactive    => 1,
    isopen      => 1,
    transitions => [
      ['UNCONFIRMED', 0],
      ['CONFIRMED',   0],
      ['NEW',         0],
      ['IN_PROGRESS', 0],
      ['RESOLVED',    0]
    ],
  },
  {
    value       => 'IN_PROGRESS',
    sortkey     => 500,
    isactive    => 1,
    isopen      => 1,
    transitions => [
      ['UNCONFIRMED', 0],
      ['CONFIRMED',   0],
      ['NEW',         0],
      ['ASSIGNED',    0],
      ['RESOLVED',    0]
    ],
  },
  {
    value       => 'REOPENED',
    sortkey     => 600,
    isactive    => 1,
    isopen      => 1,
    transitions => [
      ['UNCONFIRMED', 0],
      ['CONFIRMED',   0],
      ['NEW',         0],
      ['ASSIGNED',    0],
      ['IN_PROGRESS', 0],
      ['RESOLVED',    0]
    ],
  },
  {
    value    => 'RESOLVED',
    sortkey  => 700,
    isactive => 1,
    isopen   => 0,
    transitions =>
      [['UNCONFIRMED', 0], ['CONFIRMED', 0], ['REOPENED', 0], ['VERIFIED', 0]],
  },
  {
    value    => 'VERIFIED',
    sortkey  => 800,
    isactive => 1,
    isopen   => 0,
    transitions =>
      [['UNCONFIRMED', 0], ['CONFIRMED', 0], ['REOPENED', 0], ['RESOLVED', 0]],
  },
  {
    value    => 'CLOSED',
    sortkey  => 900,
    isactive => 1,
    isopen   => 0,
    transitions =>
      [['UNCONFIRMED', 0], ['CONFIRMED', 0], ['REOPENED', 0], ['RESOLVED', 0]],
  },
);

if ($dbh->selectrow_array("SELECT 1 FROM bug_status WHERE value = 'ASSIGNED'"))
{
  $dbh->do('DELETE FROM bug_status');
  $dbh->do('DELETE FROM status_workflow');

  print "creating status workflow...\n";

  # One pass to add the status entries.
  foreach my $status (@statuses) {
    next if !$status->{value};
    $dbh->do(
      'INSERT INTO bug_status (value, sortkey, isactive, is_open) VALUES (?, ?, ?, ?)',
      undef,
      ($status->{value}, $status->{sortkey}, $status->{isactive}, $status->{isopen})
    );
  }

  # Another pass to add the transitions.
  foreach my $status (@statuses) {
    my $old_id;
    if ($status->{value}) {
      my $from_status = new Bugzilla::Status({name => $status->{value}});
      $old_id = $from_status->{id};
    }
    else {
      $old_id = undef;
    }

    foreach my $transition (@{$status->{transitions}}) {
      my $to_status = new Bugzilla::Status({name => $transition->[0]});

      $dbh->do(
        'INSERT INTO status_workflow (old_status, new_status, require_comment) VALUES (?, ?, ?)',
        undef,
        ($old_id, $to_status->{id}, $transition->[1])
      );
    }
  }
}

##########################################################################
# Create Bugs
##########################################################################

# login to bugzilla
my $admin_user = Bugzilla::User->check($config->{admin_user_login});
Bugzilla->set_user($admin_user);

my %field_values = (
  'priority'     => 'Highest',
  'bug_status'   => 'CONFIRMED',
  'version'      => 'unspecified',
  'bug_file_loc' => '',
  'comment'      => 'please ignore this bug',
  'component'    => 'TestComponent',
  'rep_platform' => 'All',
  'short_desc'   => 'This is a testing bug only',
  'product'      => 'TestProduct',
  'op_sys'       => 'Linux',
  'bug_severity' => 'normal',
  'groups'       => [],
);

print "creating bugs...\n";
Bugzilla::Bug->create(\%field_values);
if (Bugzilla::Bug->new('public_bug')->{error}) {

  # The deadline must be set so that this bug can be used to test
  # timetracking fields using WebServices.
  Bugzilla::Bug->create(
    {%field_values, alias => 'public_bug', deadline => '2010-01-01'});
}

##########################################################################
# Create Classifications
##########################################################################
my @classifications = (
  {name => "Class2_QA", description => "required by Selenium... DON'T DELETE"},
);

print "creating classifications...\n";
foreach my $class (@classifications) {
  my $new_class = Bugzilla::Classification->new({name => $class->{name}});
  if (!$new_class) {
    $dbh->do('INSERT INTO classifications (name, description) VALUES (?, ?)',
      undef, ($class->{name}, $class->{description}));
  }
}

##########################################################################
# Create Products
##########################################################################
my $default_platform_id = $dbh->selectcol_arrayref(
  "SELECT id FROM rep_platform WHERE value = 'Unspecified'");
my $default_op_sys_id = $dbh->selectcol_arrayref(
  "SELECT id FROM op_sys WHERE value = 'Unspecified'");

my @products = (
  {
    product_name     => 'QA-Selenium-TEST',
    description      => "used by Selenium test.. DON'T DELETE",
    versions         => ['unspecified', 'QAVersion'],
    milestones       => ['QAMilestone'],
    defaultmilestone => '---',
    components       => [{
      name             => "QA-Selenium-TEST",
      description      => "used by Selenium test.. DON'T DELETE",
      initialowner     => $config->{QA_Selenium_TEST_user_login},
      initialqacontact => $config->{QA_Selenium_TEST_user_login},
      initial_cc       => [$config->{QA_Selenium_TEST_user_login}],

    }],
    default_platform_id => $default_platform_id,
    default_op_sys_id   => $default_op_sys_id,
  },

  {
    product_name     => 'Another Product',
    description      => "Alternate product used by Selenium. <b>Do not edit!</b>",
    versions         => ['unspecified', 'Another1', 'Another2'],
    milestones       => ['AnotherMS1', 'AnotherMS2', 'Milestone'],
    defaultmilestone => '---',

    components => [
      {
        name             => "c1",
        description      => "c1",
        initialowner     => $config->{permanent_user},
        initialqacontact => '',
        initial_cc       => [],

      },
      {
        name             => "c2",
        description      => "c2",
        initialowner     => $config->{permanent_user},
        initialqacontact => '',
        initial_cc       => [],

      },
    ],
    default_platform_id => $default_platform_id,
    default_op_sys_id   => $default_op_sys_id,
  },

  {
    product_name => 'C2 Forever',
    description  => 'I must remain in the Class2_QA classification '
      . 'in all cases! Do not edit!',
    classification   => 'Class2_QA',
    versions         => ['unspecified', 'C2Ver'],
    milestones       => ['C2Mil'],
    defaultmilestone => '---',
    components       => [{
      name             => "Helium",
      description      => "Feel free to add bugs to me",
      initialowner     => $config->{permanent_user},
      initialqacontact => '',
      initial_cc       => [],

    }],
    default_platform_id => $default_platform_id,
    default_op_sys_id   => $default_op_sys_id,
  },

  {
    product_name     => 'QA Entry Only',
    description      => 'Only the QA group may enter bugs here.',
    versions         => ['unspecified'],
    milestones       => [],
    defaultmilestone => '---',
    components       => [{
      name             => "c1",
      description      => "Same name as Another Product's component",
      initialowner     => $config->{QA_Selenium_TEST_user_login},
      initialqacontact => '',
      initial_cc       => [],
    }],
    default_platform_id => $default_platform_id,
    default_op_sys_id   => $default_op_sys_id,
  },

  {
    product_name     => 'QA Search Only',
    description      => 'Only the QA group may search for bugs here.',
    versions         => ['unspecified'],
    milestones       => [],
    defaultmilestone => '---',
    components       => [{
      name             => "c1",
      description      => "Still same name as the Another component",
      initialowner     => $config->{QA_Selenium_TEST_user_login},
      initialqacontact => '',
      initial_cc       => [],
    }],
    default_platform_id => $default_platform_id,
    default_op_sys_id   => $default_op_sys_id,
  },
);

print "creating products...\n";
foreach my $product (@products) {
  my $new_product = Bugzilla::Product->new({name => $product->{product_name}});
  if (!$new_product) {
    my $class_id = 1;
    if ($product->{classification}) {
      $class_id
        = Bugzilla::Classification->new({name => $product->{classification}})->id;
    }
    $dbh->do(
      'INSERT INTO products (name, description, classification_id, default_platform_id, default_op_sys_id)
                  VALUES (?, ?, ?, ?, ?)',
      undef,
      (
        $product->{product_name}, $product->{description},
        $class_id,                $new_product->{default_platform_id},
        $new_product->{default_op_sys_id}
      )
    );

    $new_product = new Bugzilla::Product({name => $product->{product_name}});

    $dbh->do('INSERT INTO milestones (product_id, value) VALUES (?, ?)',
      undef, ($new_product->id, $product->{defaultmilestone}));

    # Now clear the internal list of accessible products.
    delete Bugzilla->user->{selectable_products};

    foreach my $component (@{$product->{components}}) {

      # BMO Change for ComponentWatching extension
      my $watch_user
        = lc($component->{name}) . '@' . lc($new_product->name) . '.bugs';
      $watch_user =~ s/\s+/\-/g;

      Bugzilla::User->create({
        login_name    => $watch_user,
        cryptpassword => Bugzilla->passwdqc->generate_password(),
        disable_mail  => 1,
      });

      my %params = %{Bugzilla->input_params};
      $params{watch_user} = $watch_user;
      Bugzilla->input_params(\%params);

      Bugzilla::Component->create({
        name             => $component->{name},
        product          => $new_product,
        description      => $component->{description},
        initialowner     => $component->{initialowner},
        initialqacontact => $component->{initialqacontact},
        initial_cc       => $component->{initial_cc},
      });
    }
  }

  foreach my $version (@{$product->{versions}}) {
    if (!new Bugzilla::Version({name => $version, product => $new_product})) {
      Bugzilla::Version->create({value => $version, product => $new_product});
    }
  }

  foreach my $milestone (@{$product->{milestones}}) {
    if (!new Bugzilla::Milestone({name => $milestone, product => $new_product})) {

      # We don't use Bugzilla::Milestone->create because we want to
      # bypass security checks.
      $dbh->do('INSERT INTO milestones (product_id, value) VALUES (?,?)',
        undef, $new_product->id, $milestone);
    }
  }
}

##########################################################################
# Create Groups
##########################################################################
# create Master group
my ($group_name, $group_desc)
  = ("Master", "Master Selenium Group <b>DO NOT EDIT!</b>");

print "creating groups...\n";
if (!Bugzilla::Group->new({name => $group_name})) {
  my $group
    = Bugzilla::Group->create({
    name => $group_name, description => $group_desc, isbuggroup => 1
    });

  $dbh->do(
    'INSERT INTO group_control_map
              (group_id, product_id, entry, membercontrol, othercontrol, canedit)
              SELECT ?, products.id, 0, ?, ?, 0 FROM products', undef,
    ($group->id, CONTROLMAPSHOWN, CONTROLMAPSHOWN)
  );
}

# create QA-Selenium-TEST group. Do not use Group->create() so that
# the admin group doesn't inherit membership (yes, that's what we want!).
($group_name, $group_desc)
  = ("QA-Selenium-TEST", "used by Selenium test.. DON'T DELETE");

if (!Bugzilla::Group->new({name => $group_name})) {
  $dbh->do(
    'INSERT INTO groups (name, description, isbuggroup, isactive)
              VALUES (?, ?, 1, 1)', undef, ($group_name, $group_desc)
  );
}

# BMO 'editbugs' is also a member of 'canconfirm'
my $editbugs   = Bugzilla::Group->new({name => 'editbugs'});
my $canconfirm = Bugzilla::Group->new({name => 'canconfirm'});
$dbh->do('INSERT INTO group_group_map VALUES (?, ?, 0)',
  undef, $editbugs->id, $canconfirm->id);

# BMO: Update default security group settings for new products
my $default_security_group
  = Bugzilla::Group->new({name => 'core-security-release'});
$default_security_group ||= Bugzilla::Group->new({name => 'Master'});
if ($default_security_group) {
  $dbh->do(
    'UPDATE products SET security_group_id = ? WHERE security_group_id IS NULL',
    undef, $default_security_group->id);
}

##########################################################################
# Add Users to Groups
##########################################################################
my @users_groups = (
  {user => $config->{QA_Selenium_TEST_user_login}, group => 'QA-Selenium-TEST'},
  {user => $config->{tweakparams_user_login},      group => 'tweakparams'},
  {user => $config->{canconfirm_user_login},       group => 'canconfirm'},
  {user => $config->{editbugs_user_login},         group => 'editbugs'},
);

print "adding users to groups...\n";
foreach my $user_group (@users_groups) {

  my $group = new Bugzilla::Group({name => $user_group->{group}});
  my $user = new Bugzilla::User({name => $user_group->{user}});

  my $sth_add_mapping = $dbh->prepare(
    qq{INSERT INTO user_group_map (user_id, group_id, isbless, grant_type)
           VALUES (?, ?, ?, ?)}
  );

  # Don't crash if the entry already exists.
  eval { $sth_add_mapping->execute($user->id, $group->id, 0, GRANT_DIRECT); };
}

##########################################################################
# Associate Products with groups
##########################################################################
# Associate the QA-Selenium-TEST group with the QA-Selenium-TEST.
my $created_group = new Bugzilla::Group({name => 'QA-Selenium-TEST'});
my $secret_product = new Bugzilla::Product({name => 'QA-Selenium-TEST'});
my $no_entry       = new Bugzilla::Product({name => 'QA Entry Only'});
my $no_search      = new Bugzilla::Product({name => 'QA Search Only'});

print "restricting products to groups...\n";

# Don't crash if the entries already exist.
my $sth = $dbh->prepare(
  'INSERT INTO group_control_map
                         (group_id, product_id, entry, membercontrol, othercontrol, canedit)
                         VALUES (?, ?, ?, ?, ?, ?)'
);
eval {
  $sth->execute($created_group->id, $secret_product->id, 1, CONTROLMAPMANDATORY,
    CONTROLMAPMANDATORY, 0);
};
eval {
  $sth->execute($created_group->id, $no_entry->id, 1, CONTROLMAPNA, CONTROLMAPNA,
    0);
};
eval {
  $sth->execute($created_group->id, $no_search->id, 0, CONTROLMAPMANDATORY,
    CONTROLMAPMANDATORY, 0);
};

##########################################################################
# Create flag types
##########################################################################
my @flagtypes = (
  {
    name             => 'spec_multi_flag',
    desc             => 'Specifically requestable and multiplicable bug flag',
    is_requestable   => 1,
    is_requesteeble  => 1,
    is_multiplicable => 1,
    grant_group      => 'editbugs',
    target_type      => 'b',
    cc_list          => '',
    inclusions       => ['Another Product:c1']
  },
);

print "creating flag types...\n";
foreach my $flag (@flagtypes) {

# The name is not unique, even within a single product/component, so there is NO WAY
# to know if the existing flag type is the one we want or not.
# As our Selenium scripts would be confused anyway if there is already such a flag name,
# we simply skip it and assume the existing flag type is the one we want.
  next if new Bugzilla::FlagType({name => $flag->{name}});

  my $grant_group_id
    = $flag->{grant_group}
    ? Bugzilla::Group->new({name => $flag->{grant_group}})->id
    : undef;
  my $request_group_id
    = $flag->{request_group}
    ? Bugzilla::Group->new({name => $flag->{request_group}})->id
    : undef;

  $dbh->do(
    'INSERT INTO flagtypes (name, description, cc_list, target_type, is_requestable,
                                     is_requesteeble, is_multiplicable, grant_group_id, request_group_id)
                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    undef,
    (
      $flag->{name},             $flag->{desc},
      $flag->{cc_list},          $flag->{target_type},
      $flag->{is_requestable},   $flag->{is_requesteeble},
      $flag->{is_multiplicable}, $grant_group_id,
      $request_group_id
    )
  );

  my $type_id = $dbh->bz_last_key('flagtypes', 'id');

  foreach my $inclusion (@{$flag->{inclusions}}) {
    my ($product, $component) = split(':', $inclusion);
    my ($prod_id, $comp_id);
    if ($product) {
      my $prod_obj = Bugzilla::Product->new({name => $product});
      $prod_id = $prod_obj->id;
      if ($component) {
        $comp_id
          = Bugzilla::Component->new({name => $component, product => $prod_obj})->id;
      }
    }
    $dbh->do(
      'INSERT INTO flaginclusions (type_id, product_id, component_id)
                  VALUES (?, ?, ?)', undef, ($type_id, $prod_id, $comp_id)
    );
  }
}

##########################################################################
# Create custom fields
##########################################################################
my @fields = (
  {
    name        => 'cf_QA_status',
    description => 'QA Status',
    type        => FIELD_TYPE_MULTI_SELECT,
    sortkey     => 100,
    mailhead    => 0,
    enter_bug   => 1,
    obsolete    => 0,
    custom      => 1,
    values      => ['verified', 'in progress', 'untested']
  },
  {
    name        => 'cf_single_select',
    description => 'SingSel',
    type        => FIELD_TYPE_SINGLE_SELECT,
    sortkey     => 200,
    mailhead    => 0,
    enter_bug   => 1,
    custom      => 1,
    obsolete    => 0,
    values      => [qw(one two three)],
  },
);

print "creating custom fields...\n";
foreach my $f (@fields) {

  # Skip existing custom fields.
  next if Bugzilla::Field->new({name => $f->{name}});

  my @values;
  if (exists $f->{values}) {
    @values = @{$f->{values}};

    # We have to delete this key, else create() will complain
    # that 'values' is not an existing column name.
    delete $f->{values};
  }
  Bugzilla::Field->create($f);
  my $field = Bugzilla::Field->new({name => $f->{name}});

  # Now populate the table with valid values, if necessary.
  next unless scalar @values;

  my $sth = $dbh->prepare('INSERT INTO ' . $field->name . ' (value) VALUES (?)');
  foreach my $value (@values) {
    $sth->execute($value);
  }
}

####################################################################
# Set Parameters That Require Other Things To Have Been Done First #
####################################################################

if (Bugzilla->params->{insidergroup} ne 'QA-Selenium-TEST') {
  SetParam('insidergroup', 'QA-Selenium-TEST');
  $params_modified = 1;
}

if ($params_modified) {
  write_params();
  print <<EOT;
** Parameters have been modified by this script. Please re-run
** checksetup.pl to set file permissions on data/params correctly.

EOT
}

########################
# Create a Private Bug #
########################

my $test_user = Bugzilla::User->check($config->{QA_Selenium_TEST_user_login});
Bugzilla->set_user($test_user);

print "Creating private bug(s)...\n";
if (Bugzilla::Bug->new('private_bug')->{error}) {
  my %priv_values = %field_values;
  $priv_values{alias}     = 'private_bug';
  $priv_values{product}   = 'QA-Selenium-TEST';
  $priv_values{component} = 'QA-Selenium-TEST';
  my $bug = Bugzilla::Bug->create(\%priv_values);
}

######################
# Create Attachments #
######################

# BMO FIXME: Users must be in 'editbugs' to set their own
# content type other than text/plain or application/octet-stream
$group = new Bugzilla::Group({name => 'editbugs'});
my $sth_add_mapping = $dbh->prepare(
  qq{INSERT INTO user_group_map (user_id, group_id, isbless, grant_type)
       VALUES (?, ?, ?, ?)}
);

# Don't crash if the entry already exists.
eval {
  $sth_add_mapping->execute(Bugzilla->user->id, $group->id, 0, GRANT_DIRECT);
};

print "creating attachments...\n";

# We use the contents of this script as the attachment.
open(my $attachment_fh, '<', __FILE__) or die __FILE__ . ": $!";

my $attachment_contents;
{ local $/; $attachment_contents = <$attachment_fh>; }

close($attachment_fh);

foreach my $alias (qw(public_bug private_bug)) {
  my $bug = Bugzilla::Bug->new($alias);
  foreach my $is_private (0, 1) {
    Bugzilla::Attachment->create({
      bug         => $bug,
      data        => $attachment_contents,
      description => "${alias}_${is_private}",
      filename    => "${alias}_${is_private}.pl",
      mimetype    => 'application/x-perl',
      isprivate   => $is_private,
    });
  }
}

# BMO FIXME: Remove test user from 'editbugs' group
my $sth_remove_mapping = $dbh->prepare(
  qq{DELETE FROM user_group_map WHERE user_id = ?
       AND group_id = ? AND isbless = 0 AND grant_type = ?}
);

# Don't crash if the entry already exists.
eval {
  $sth_remove_mapping->execute(Bugzilla->user->id, $group->id, GRANT_DIRECT);
};

###################
# Create Keywords #
###################

my @keywords = (
  {
    name        => 'test-keyword-1',
    description => 'Created for Bugzilla QA Tests, Keyword 1'
  },
  {
    name        => 'test-keyword-2',
    description => 'Created for Bugzilla QA Tests, Keyword 2'
  },
);

print "creating keywords...\n";
foreach my $kw (@keywords) {
  next if new Bugzilla::Keyword({name => $kw->{name}});
  Bugzilla::Keyword->create($kw);
}

############################
# Install the QA extension #
############################

print "copying the QA extension...\n";
dircopy("$conf_path/qa/extensions/QA", "$conf_path/extensions/QA");

my $cwd = cwd();
chdir($conf_path);
system("perl", "scripts/fixperms.pl");
chdir($cwd);

print "installation and configuration complete!\n";
