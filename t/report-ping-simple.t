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
  unlink('data/db/report_ping_simple') if -f 'data/db/report_ping_simple';
  $ENV{test_db_name} = 'report_ping_simple';
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
use ok 'Bugzilla::Report::Ping::Simple';

Bugzilla->dbh->model->resultset('Keyword')
  ->create({name => 'regression', description => 'the regression keyword'});

my $user = create_user('reportuser@invalid.tld', '*');
Bugzilla->set_user($user);
create_bug(
  short_desc  => "test bug $_",
  comment     => "Hello, world: $_",
  provided $_ % 3 == 0, keywords => ['regression'],
  assigned_to => 'reportuser@invalid.tld'
) for (1..250);

my $report = Bugzilla::Report::Ping::Simple->new(
  base_url => 'http://localhost',
  model => Bugzilla->dbh->model,
);

my $rs = $report->resultset->page(1);
is($rs->count, 10, "got 10 items");
my $pager = $rs->pager;
is($pager->last_page, 25, "got 25 pages");

is($rs->first->id, 1, "first bug of page 1 is 1");

my ($first, $second, $third, @rest) = $rs->all;
{
  my ($id, $doc) = $report->prepare( $first );
  is($id, 1, "doc id is 1");
  is($doc->{product}, 'Firefox');
  is($doc->{keywords}, []);
  is([map { "$_" } $report->validate($doc)], [], "No errors for first doc");
}

{
  my ($id, $doc) = $report->prepare( $third );
  is($id, 3, "doc id is 3");
  is($doc->{product}, 'Firefox');
  is($doc->{keywords}, ['regression']);
}

{
  my $rs2 = $rs->page($pager->next_page);
  my $pager2 = $rs2->pager;

  is($rs2->first->id, 11, "first bug of page 2 is 11");
  isnt($pager, $pager2, "pagers are different");
}

done_testing;

