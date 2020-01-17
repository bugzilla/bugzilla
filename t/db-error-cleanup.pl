#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE} = 'log4perl-t.conf';
  $ENV{test_db_name}         = 'db_errors';
}

END { unlink('data/db/db_errors') }

use Bugzilla::Test::MockLocalconfig (urlbase => 'http://bmo.test');
use Bugzilla::Test::MockDB;
use Test2::V0;
use Test2::Tools::Exception qw(dies lives);
use Try::Tiny;
use Bugzilla::Test::Util qw(create_user);

ok(
  dies {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction;
    create_user('example@user.org', '*');
    $dbh->dbh->disconnect;
    $dbh->dbh;
  },
  "connecting after a disconnect in a bz transaction is fatal"
) and note($@);

ok(lives { Bugzilla->_cleanup }, "_cleanup") or note($@);

ok(!Bugzilla->request_cache->{dbh}, "dbh should be gone after cleanup");

my $user = Bugzilla::User->new({name => 'example@user.org'});
ok(!$user, 'user was not created');

ok(
  dies {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction;
    create_user('example@user.org', '*');
    $dbh->dbh->disconnect;
    $dbh->bz_commit_transaction;
  },
  "commit after a disconnect is fatal"
) and note($@);

ok(lives { Bugzilla->_cleanup }, "_cleanup") or note($@);

ok(
  lives {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction;
    create_user('example@user.org', '*');
    $dbh->dbh->disconnect;
    Bugzilla->_cleanup;
    $dbh->dbh;
  },
  "calling _cleanup after bz_start_transaction results in a working connection",
) or note($@);


done_testing;
