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

BEGIN {
  unlink('data/db/model_test') if -f 'data/db/model_test';
  $ENV{test_db_name} = 'model_test';
}

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');
use Bugzilla::Test::Util qw(create_bug create_user);
use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Hook;
BEGIN { Bugzilla->extensions }
use Test2::V0;
use Test2::Tools::Mock qw(mock mock_accessor);
use Test2::Tools::Exception qw(dies lives);
use PerlX::Maybe qw(provided);

Bugzilla->dbh->model->resultset('Keyword')
  ->create({name => 'regression', description => 'the regression keyword'});

my $user = create_user('reportuser@invalid.tld', '*');
$user->{groups} = [Bugzilla::Group->get_all];
Bugzilla->set_user($user);

create_bug(
  short_desc  => "test bug $_",
  comment     => "Hello, world: $_",
  provided $_ % 3 == 0, keywords => ['regression'],
  assigned_to => 'reportuser@invalid.tld'
) for (1..10);

my $model = Bugzilla->dbh->model;
my $bug3 = $model->resultset('Bug')->find(3);
isa_ok($bug3, 'Bugzilla::Model::Result::Bug');

is([map { $_->name } $bug3->keywords->all], ['regression']);

is($bug3->reporter->login_name, Bugzilla::Bug->new($bug3->id)->reporter->login);


done_testing;

