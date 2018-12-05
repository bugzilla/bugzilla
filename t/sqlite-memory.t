# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.10.1;
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );
use Test::More;
use Test2::Tools::Mock;
use Try::Tiny;
use Capture::Tiny qw(capture_merged);
use Bugzilla::Test::MockParams;

BEGIN {
  $ENV{LOCALCONFIG_ENV} = 'BMO';
  $ENV{BMO_db_driver}   = 'sqlite';
  $ENV{BMO_db_name}     = ':memory:';
}
use Bugzilla;
BEGIN { Bugzilla->extensions }


isa_ok(Bugzilla->dbh, 'Bugzilla::DB::Sqlite');

use ok 'Bugzilla::Install';
use ok 'Bugzilla::Install::DB';

my $lives_ok = sub {
  my ($desc, $code) = @_;
  my $output;
  try {
    $output = capture_merged { $code->() };
    pass($desc);
  }
  catch {
    diag $_;
    fail($desc);
  }
  finally {
    diag "OUTPUT: $output" if $output;
  };
};

my $output = '';
$lives_ok->(
  'bz_setup_database' => sub {
    Bugzilla->dbh->bz_setup_database;
  }
);

$lives_ok->(
  'bz_populate_enum_tables' => sub {

    # Populate the tables that hold the values for the <select> fields.
    Bugzilla->dbh->bz_populate_enum_tables();
  }
);

$lives_ok->(
  'update_fielddefs_definition' => sub {
    Bugzilla::Install::DB::update_fielddefs_definition();
  }
);

$lives_ok->(
  'populate_field_definitions' => sub {
    Bugzilla::Field::populate_field_definitions();
  }
);

$lives_ok->(
  'init_workflow' => sub {
    Bugzilla::Install::init_workflow();
  }
);

$lives_ok->(
  'update_table_definitions' => sub {
    Bugzilla::Install::DB->update_table_definitions({});
  }
);

$lives_ok->(
  'update_system_groups' => sub {
    Bugzilla::Install::update_system_groups();
  }
);

# "Log In" as the fake superuser who can do everything.
Bugzilla->set_user(Bugzilla::User->super_user);

$lives_ok->(
  'update_settings' => sub {
    Bugzilla::Install::update_settings();
  }
);

SKIP: {
  skip 'default product cannot be created without default assignee', 1;
  $lives_ok->(
    'create_default_product' => sub {
      Bugzilla::Install::create_default_product();
    }
  );
}

done_testing;
