#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# -*- Mode: perl; indent-tabs-mode: nil -*-

use 5.14.0;
use strict;
use warnings;

use Cwd;

my $conf_path;
my $config;

BEGIN {
  say 'reading the config file...';
  my $conf_file = 'selenium_test.conf';
  $config = do "$conf_file" or die "can't read configuration '$conf_file': $!$@";

  $conf_path = $config->{bugzilla_path};

  # We don't want randomly-generated keys. We want the ones specified
  # in the config file so that we can use them in tests scripts.
  *Bugzilla::User::APIKey::_check_api_key = sub { return $_[1]; };
}

use lib $conf_path, "$conf_path/local/lib/perl5";

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
use Bugzilla::User::APIKey;

my $dbh = Bugzilla->dbh;

# set Bugzilla usage mode to USAGE_MODE_CMDLINE
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

##########################################################################
# Set Parameters
##########################################################################

# Some parameters must be turned on to create bugs requiring them.
# They are also expected to be turned on by some webservice_*.t scripts.
my ($urlbase, $sslbase);
$urlbase = $config->{browser_url} . '/' . $config->{bugzilla_installation};
$urlbase .= '/' unless $urlbase =~ /\/$/;

if ($urlbase =~ /^https/) {
  $sslbase = $urlbase;
  $urlbase =~ s/^https(.+)$/http$1/;
}

my %set_params = (
  urlbase              => $urlbase,
  sslbase              => $sslbase,
  useqacontact         => 1,
  mail_delivery_method => 'Test',
  maxattachmentsize    => 256,
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
  Bugzilla::User::Setting::set_default($pref, $value, 0);
}

##########################################################################
# Create Users
##########################################################################

# First of all, remove the default .* regexp for the editbugs group.
my $group = Bugzilla::Group->new({name => 'editbugs'});
$group->set_user_regexp('');
$group->update();

my @usernames = (
  'admin',       'no-privs',       'QA-Selenium-TEST', 'canconfirm',
  'tweakparams', 'permanent_user', 'editbugs',         'disabled',
);

say 'creating user accounts...';
foreach my $username (@usernames) {
  my ($password, $login);

  my $prefix = $username;
  if ($username eq 'permanent_user') {
    $password = $config->{admin_user_passwd};
    $login    = $config->{$username};
  }
  elsif ($username eq 'no-privs') {
    $prefix = 'unprivileged';
  }
  elsif ($username eq 'QA-Selenium-TEST') {
    $prefix = 'QA_Selenium_TEST';
  }

  $password ||= $config->{"${prefix}_user_passwd"};
  $login    ||= $config->{"${prefix}_user_login"};
  my $api_key = $config->{"${prefix}_user_api_key"};

  if (is_available_email($login)) {
    my %extra_args;
    if ($username eq 'disabled') {
      $extra_args{disabledtext} = '!!This is the text!!';
    }

    my $user = Bugzilla::User->create({
      login_name    => $login,
      email         => $login,
      realname      => $username,
      cryptpassword => $password,
      %extra_args,
    });

    if ($api_key) {
      Bugzilla::User::APIKey->create({
        user_id     => $user->id,
        description => 'API key for QA tests',
        api_key     => $api_key
      });
    }

    if ($username eq 'admin' or $username eq 'permanent_user') {
      Bugzilla::Install::make_admin($login);
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
);

say 'creating bugs...';
my $bug = Bugzilla::Bug->create(\%field_values);
say 'Bug ' . $bug->id . ' created';
if (Bugzilla::Bug->new('public_bug')->{error}) {

  # The deadline must be set so that this bug can be used to test
  # timetracking fields using WebServices.
  $bug = Bugzilla::Bug->create(
    {%field_values, alias => 'public_bug', deadline => '2010-01-01'});
  say 'Bug ' . $bug->id . ' (alias: public_bug) created';
}

##########################################################################
# Create Classifications
##########################################################################

my @classifications = (
  {name => 'Class2_QA', description => "required by Selenium... DON'T DELETE"},
);

say 'creating classifications...';
for my $class (@classifications) {
  my $new_class = Bugzilla::Classification->new({name => $class->{name}});
  if (!$new_class) {
    $dbh->do('INSERT INTO classifications (name, description) VALUES (?, ?)',
      undef, ($class->{name}, $class->{description}));
  }
}
##########################################################################
# Create Products
##########################################################################

my @products = (
  {
    product_name     => 'QA-Selenium-TEST',
    description      => "used by Selenium test.. DON'T DELETE",
    versions         => ['unspecified', 'QAVersion'],
    milestones       => ['QAMilestone'],
    defaultmilestone => '---',
    components       => [{
      name             => 'QA-Selenium-TEST',
      description      => "used by Selenium test.. DON'T DELETE",
      initialowner     => $config->{QA_Selenium_TEST_user_login},
      initialqacontact => $config->{QA_Selenium_TEST_user_login},
      initial_cc       => [$config->{QA_Selenium_TEST_user_login}],
    }],
  },

  {
    product_name     => 'Another Product',
    description      => 'Alternate product used by Selenium. <b>Do not edit!</b>',
    versions         => ['unspecified', 'Another1', 'Another2'],
    milestones       => ['AnotherMS1', 'AnotherMS2', 'Milestone'],
    defaultmilestone => '---',
    components       => [
      {
        name             => 'c1',
        description      => 'c1',
        initialowner     => $config->{permanent_user},
        initialqacontact => '',
        initial_cc       => [],
      },
      {
        name             => 'c2',
        description      => 'c2',
        initialowner     => $config->{permanent_user},
        initialqacontact => '',
        initial_cc       => [],
      },
    ],
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
      name             => 'Helium',
      description      => 'Feel free to add bugs to me',
      initialowner     => $config->{permanent_user},
      initialqacontact => '',
      initial_cc       => [],
    }],
  },

  {
    product_name     => 'QA Entry Only',
    description      => 'Only the QA group may enter bugs here.',
    versions         => ['unspecified'],
    milestones       => [],
    defaultmilestone => '---',
    components       => [{
      name             => 'c1',
      description      => "Same name as Another Product's component",
      initialowner     => $config->{QA_Selenium_TEST_user_login},
      initialqacontact => '',
      initial_cc       => [],
    }],
  },

  {
    product_name     => 'QA Search Only',
    description      => 'Only the QA group may search for bugs here.',
    versions         => ['unspecified'],
    milestones       => [],
    defaultmilestone => '---',
    components       => [{
      name             => 'c1',
      description      => 'Still same name as the Another component',
      initialowner     => $config->{QA_Selenium_TEST_user_login},
      initialqacontact => '',
      initial_cc       => [],
    }],
  },
);

say 'creating products...';
foreach my $product (@products) {
  my $new_product = Bugzilla::Product->new({name => $product->{product_name}});
  if (!$new_product) {
    my $class_id = 1;
    if ($product->{classification}) {
      $class_id
        = Bugzilla::Classification->new({name => $product->{classification}})->id;
    }
    $dbh->do(
      'INSERT INTO products (name, description, classification_id) VALUES (?, ?, ?)',
      undef,
      ($product->{product_name}, $product->{description}, $class_id)
    );

    $new_product = Bugzilla::Product->new({name => $product->{product_name}});

    $dbh->do('INSERT INTO milestones (product_id, value) VALUES (?, ?)',
      undef, ($new_product->id, $product->{defaultmilestone}));

    # Now clear the internal list of accessible products.
    delete Bugzilla->user->{selectable_products};

    foreach my $component (@{$product->{components}}) {
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
    my $new_version
      = Bugzilla::Version->new({name => $version, product => $new_product});
    if (!$new_version) {
      Bugzilla::Version->create({value => $version, product => $new_product});
    }
  }

  foreach my $milestone (@{$product->{milestones}}) {
    my $new_milestone
      = Bugzilla::Milestone->new({name => $milestone, product => $new_product});
    if (!$new_milestone) {

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
  = ('Master', 'Master Selenium Group <b>DO NOT EDIT!</b>');

say 'creating groups...';
my $new_group = Bugzilla::Group->new({name => $group_name});
if (!$new_group) {
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
  = ('QA-Selenium-TEST', "used by Selenium test.. DON'T DELETE");

$new_group = Bugzilla::Group->new({name => $group_name});
if (!$new_group) {
  $dbh->do(
    'INSERT INTO groups (name, description, isbuggroup, isactive)
              VALUES (?, ?, 1, 1)', undef, ($group_name, $group_desc)
  );
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

say 'adding users to groups...';
foreach my $user_group (@users_groups) {
  my $group = Bugzilla::Group->new({name => $user_group->{group}});
  my $user = Bugzilla::User->new({name => $user_group->{user}});

  my $sth_add_mapping = $dbh->prepare(
    'INSERT INTO user_group_map (user_id, group_id, isbless, grant_type)
                     VALUES (?, ?, ?, ?)'
  );

  # Don't crash if the entry already exists.
  eval { $sth_add_mapping->execute($user->id, $group->id, 0, GRANT_DIRECT); };
}

##########################################################################
# Associate Products with groups
##########################################################################

# Associate the QA-Selenium-TEST group with the QA-Selenium-TEST.
my $created_group = Bugzilla::Group->new({name => 'QA-Selenium-TEST'});
my $secret_product = Bugzilla::Product->new({name => 'QA-Selenium-TEST'});
my $no_entry       = Bugzilla::Product->new({name => 'QA Entry Only'});
my $no_search      = Bugzilla::Product->new({name => 'QA Search Only'});

say 'restricting products to groups...';

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

say 'creating flag types...';
foreach my $flag (@flagtypes) {

# The name is not unique, even within a single product/component, so there is NO WAY
# to know if the existing flag type is the one we want or not.
# As our Selenium scripts would be confused anyway if there is already such a flag name,
# we simply skip it and assume the existing flag type is the one we want.
  next if Bugzilla::FlagType->new({name => $flag->{name}});

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
    mailhead    => 0,
    enter_bug   => 1,
    custom      => 1,
    values      => [qw(one two three)],
  },
);

say 'creating custom fields...';
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
  my $field = Bugzilla::Field->create($f);

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
  write_params();
}

if (Bugzilla->params->{timetrackinggroup} ne 'editbugs') {
  SetParam('timetrackinggroup', 'editbugs');
  write_params();
}

########################
# Create a Private Bug #
########################

my $test_user = Bugzilla::User->check($config->{QA_Selenium_TEST_user_login});
$test_user->{'groups'} = [
  Bugzilla::Group->new({name => 'editbugs'}),
  Bugzilla::Group->new({name => 'QA-Selenium-TEST'})
];    # editbugs is needed for alias creation
Bugzilla->set_user($test_user);

if (Bugzilla::Bug->new('private_bug')->{error}) {
  say 'Creating private bug...';
  my %priv_values = %field_values;
  $priv_values{alias}     = 'private_bug';
  $priv_values{product}   = 'QA-Selenium-TEST';
  $priv_values{component} = 'QA-Selenium-TEST';
  my $bug = Bugzilla::Bug->create(\%priv_values);
  say 'Bug ' . $bug->id . ' (alias: private_bug) created';
}

######################
# Create Attachments #
######################

say 'creating attachments...';

# We use the contents of this script as the attachment.
open(my $attachment_fh, '<', __FILE__) or die __FILE__ . ": $!";
my $attachment_contents;
{
  local $/;
  $attachment_contents = <$attachment_fh>;
}
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

say 'creating keywords...';
foreach my $kw (@keywords) {
  next if Bugzilla::Keyword->new({name => $kw->{name}});
  Bugzilla::Keyword->create($kw);
}

############################
# Install the QA extension #
############################

say 'copying the QA extension...';
my $output = `cp -R ../extensions/QA $conf_path/extensions/.`;
print $output if $output;

my $cwd = cwd();
chdir($conf_path);
$output = `perl contrib/fixperms.pl`;
print $output if $output;
chdir($cwd);

say 'installation and configuration complete!';
