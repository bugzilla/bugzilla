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

use Test2::V0;
use ok 'Bugzilla::WebService::Wants';

my $empty = Bugzilla::WebService::Wants->new(cache => {});
ok($empty->is_empty, "it is empty");
ok(!$empty->is_specific, "no include/exclude is not specific");

my $non_empty_i
  = Bugzilla::WebService::Wants->new(include_fields => ['foo'], cache => {});
ok(!($non_empty_i->is_empty), "it is not empty with includes");

my $non_empty_e
  = Bugzilla::WebService::Wants->new(exclude_fields => ['foo'], cache => {});
ok(!($non_empty_e->is_empty), "it is not empty with excludes");

my $wants = Bugzilla::WebService::Wants->new(
  exclude_fields => ['_extra'],
  include_fields => ['_custom', '_default'],
  cache          => {}
);

ok($wants->match('cf_last_resolved', ['custom', 'default']), 'cf_last_resolved is custom and default');
ok(!$wants->match('triage_owner_id', ['extra']), 'triage owner is extra');

ok($wants->exclude_type->{extra}, "extra is excluded");
ok($wants->include_type->{custom}, "custom is included");

$wants = Bugzilla::WebService::Wants->new(
  exclude_fields => ['_custom'],
  include_fields => ['cf_test'],
  cache          => {},
);

ok($wants->match('cf_test', ['default', 'custom']), "excludes are more specific");

$wants = Bugzilla::WebService::Wants->new(
  exclude_fields => ['_default'],
  include_fields => ['cf_test'],
  cache          => {},
);

ok(!$wants->is_specific, "not specific");
ok($wants->match('cf_test', ['default', 'custom']), "excludes are more specific");

is([ $wants->includes ], ['cf_test']);

$wants = Bugzilla::WebService::Wants->new(
  exclude_fields => ['cf_evil'],
  include_fields => ['cf_test'],
  cache          => {},
);
ok($wants->is_specific, "has specific wants");

done_testing;
