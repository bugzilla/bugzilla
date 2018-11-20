# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Test::MockDB;
use 5.10.1;
use strict;
use warnings;
use Try::Tiny;
use Capture::Tiny qw(capture_merged);

use Bugzilla::Test::MockLocalconfig (db_driver => 'sqlite',
  db_name => $ENV{test_db_name} // ':memory:',);
use Bugzilla;
BEGIN { Bugzilla->extensions }
use Bugzilla::Test::MockParams (emailsuffix => '', emailregexp => '.+',);
use Bugzilla::Test::Util qw(create_user);

sub import {
  require Bugzilla::Install;
  require Bugzilla::Install::DB;
  require Bugzilla::Field;

  state $first_time = 0;

  return undef if $first_time++;

  return capture_merged {
    Bugzilla->dbh->bz_setup_database();

    # Populate the tables that hold the values for the <select> fields.
    Bugzilla->dbh->bz_populate_enum_tables();

    Bugzilla::Install::DB::update_fielddefs_definition();
    Bugzilla::Field::populate_field_definitions();
    Bugzilla::Install::init_workflow();
    Bugzilla::Install::DB->update_table_definitions({});
    Bugzilla::Install::update_system_groups();

    Bugzilla->set_user(Bugzilla::User->super_user);

    Bugzilla::Install::update_settings();

    my $dbh = Bugzilla->dbh;
    if (!$dbh->selectrow_array("SELECT 1 FROM priority WHERE value = 'P1'")) {
      $dbh->do("DELETE FROM priority");
      my $count = 100;
      foreach my $priority (map {"P$_"} 1 .. 5) {
        $dbh->do("INSERT INTO priority (value, sortkey) VALUES (?, ?)",
          undef, ($priority, $count + 100));
      }
    }
    my @flagtypes = (
      {
        name             => 'review',
        desc             => 'The patch has passed review by a module owner or peer.',
        is_requestable   => 1,
        is_requesteeble  => 1,
        is_multiplicable => 1,
        grant_group      => '',
        target_type      => 'a',
        cc_list          => '',
        inclusions       => ['']
      },
      {
        name => 'feedback',
        desc => 'A particular person\'s input is requested for a patch, '
          . 'but that input does not amount to an official review.',
        is_requestable   => 1,
        is_requesteeble  => 1,
        is_multiplicable => 1,
        grant_group      => '',
        target_type      => 'a',
        cc_list          => '',
        inclusions       => ['']
      }
    );

    foreach my $flag (@flagtypes) {
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

    create_user('nobody@mozilla.org', '*');
    my @classifications = (
      {
        name        => "Client Software",
        description => "End User Products developed by mozilla.org contributors"
      },
      {
        name        => "Components",
        description => "Standalone components that can be used by other products. "
          . "Core, Directory, NSPR, NSS and Toolkit are used by Gecko "
          . "(which is in turn used by Firefox, Thunderbird, SeaMonkey, "
          . "Fennec, and others)",
      },
      {
        name        => "Server Software",
        description => "Web Server software developed by mozilla.org contributors "
          . "to aid the development of mozilla.org products"
      },
      {
        name => "Other",
        description =>
          "Everything else - websites, Labs, important things which aren't code"
      },
      {name => "Graveyard", description => "Old, retired products"},
    );

    for my $class (@classifications) {
      my $new_class = Bugzilla::Classification->new({name => $class->{name}});
      if (!$new_class) {
        $dbh->do('INSERT INTO classifications (name, description) VALUES (?, ?)',
          undef, ($class->{name}, $class->{description}));
      }
    }

    my @products = (
      {
        classification => 'Client Software',
        product_name   => 'Firefox',
        description    => 'For bugs in Firefox Desktop, the Mozilla Foundations '
          . 'web browser. For Firefox user interface issues in '
          . 'menus, developer tools, bookmarks, location bar, and '
          . 'preferences. Many Firefox bugs will either be filed '
          . 'here or in the <a href="https://bugzilla.mozilla.org/describecomponents.cgi?product=Core">Core</a> product.'
          . '(<a href="https://wiki.mozilla.org/Modules/All#Firefox">more info</a>)',
        versions =>
          ['34 Branch', '35 Branch', '36 Branch', '37 Branch', 'Trunk', 'unspecified'],
        milestones =>
          ['Firefox 36', '---', 'Firefox 37', 'Firefox 38', 'Firefox 39', 'Future'],
        defaultmilestone => '---',
        components       => [{
          name        => 'General',
          description => 'For bugs in Firefox which do not fit into '
            . 'other more specific Firefox components',
          initialowner   => 'nobody@mozilla.org',
          initialqaowner => '',
          initial_cc     => [],
          watch_user     => 'general@firefox.bugs'
        }],
      },
      {
        classification => 'Other',
        product_name   => 'bugzilla.mozilla.org',
        description    => 'For issues relating to the bugzilla.mozilla.org website, '
          . 'also known as <a href="https://wiki.mozilla.org/BMO">BMO</a>.',
        versions         => ['Development/Staging', 'Production'],
        milestones       => ['---'],
        defaultmilestone => '---',
        components       => [{
          name => 'General',
          description =>
            'This is the component for issues specific to bugzilla.mozilla.org '
            . 'that do not belong in other components.',
          initialowner   => 'nobody@mozilla.org',
          initialqaowner => '',
          initial_cc     => [],
          watch_user     => 'general@bugzilla.bugs'
        }],
      },
    );

    my $default_op_sys_id
      = $dbh->selectrow_array("SELECT id FROM op_sys WHERE value = 'Unspecified'");
    my $default_platform_id = $dbh->selectrow_array(
      "SELECT id FROM rep_platform WHERE value = 'Unspecified'");

    for my $product (@products) {
      my $new_product = Bugzilla::Product->new({name => $product->{product_name}});
      if (!$new_product) {
        my $class_id = 1;
        if ($product->{classification}) {
          $class_id
            = Bugzilla::Classification->new({name => $product->{classification}})->id;
        }
        $dbh->do(
          'INSERT INTO products (name, description, classification_id,
                                        default_op_sys_id, default_platform_id)
                  VALUES (?, ?, ?, ?, ?)',
          undef,
          (
            $product->{product_name}, $product->{description}, $class_id,
            $default_op_sys_id,       $default_platform_id
          )
        );

        $new_product = new Bugzilla::Product({name => $product->{product_name}});

        $dbh->do('INSERT INTO milestones (product_id, value) VALUES (?, ?)',
          undef, ($new_product->id, $product->{defaultmilestone}));

        # Now clear the internal list of accessible products.
        delete Bugzilla->user->{selectable_products};

        foreach my $component (@{$product->{components}}) {
          if (!Bugzilla::User->new({name => $component->{watch_user}})) {
            Bugzilla::User->create({
              login_name => $component->{watch_user}, cryptpassword => '*',
            });
          }
          Bugzilla->input_params({watch_user => $component->{watch_user}});
          Bugzilla::Component->create({
            name             => $component->{name},
            product          => $new_product,
            description      => $component->{description},
            initialowner     => $component->{initialowner},
            initialqacontact => $component->{initialqacontact} || '',
            initial_cc       => $component->{initial_cc} || [],
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
          $dbh->do('INSERT INTO milestones (product_id, value) VALUES (?,?)',
            undef, $new_product->id, $milestone);
        }
      }
    }

  };
}

1;
