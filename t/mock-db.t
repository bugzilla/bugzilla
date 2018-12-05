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
use lib qw( . lib local/lib/perl5 );
use Test::More;
use Try::Tiny;

use ok 'Bugzilla::Test::MockDB';
use ok 'Bugzilla::Test::Util', qw(create_user);

try {
  Bugzilla::Test::MockDB->import();
  pass('made fake in-memory db');
}
catch {
  diag $_;
  fail('made fake in-memory db');
};

try {
  create_user('bob@pants.gov', '*');
  ok(Bugzilla::User->new({name => 'bob@pants.gov'})->id, 'create a user');
}
catch {
  fail('create a user');
};

try {
  my $rob = create_user('rob@pants.gov', '*');
  Bugzilla::User->check({id => $rob->id});
  pass('rob@pants.gov checks out');
}
catch {
  diag $_;
  fail('rob@pants.gov fails');
};

done_testing;
