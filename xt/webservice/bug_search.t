# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

########################################
# Test for xmlrpc call to Bug.search() #
########################################

use 5.14.0;
use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../lib", "$RealBin/../../local/lib/perl5";

use QA::Util;
use QA::Tests qw(PRIVATE_BUG_USER);
use DateTime;
use List::MoreUtils qw(uniq);
use Test::More;
use Data::Dumper;

my ($config, @clients) = get_rpc_clients();
plan tests => $config->{test_extensions} ? 565 : 556;

my ($public_bug, $private_bug) = $clients[0]->bz_create_test_bugs('private');

# Add aliases to both bugs
$public_bug->{alias}  = random_string(40);
$private_bug->{alias} = random_string(40);
my $alias_tests = [
  {
    user => 'editbugs',
    args => {ids => [$public_bug->{id}], alias => $public_bug->{alias}},
    test => 'Add alias to public bug'
  },
  {
    user => PRIVATE_BUG_USER,
    args => {
      ids => [$private_bug->{id}],
      cc  => {add => [$config->{'editbugs_user_login'}]}
    },
    test => 'Add editusers to cc of private bug'
  },
  {
    user => 'editbugs',
    args => {ids => [$private_bug->{id}], alias => $private_bug->{alias}},
    test => 'Add alias to private bug'
  },
  {
    user => PRIVATE_BUG_USER,
    args => {
      ids => [$private_bug->{id}],
      cc  => {remove => [$config->{'editbugs_user_login'}]}
    },
    test => 'Remove editusers from cc of private bug'
  },
];
$clients[0]->bz_run_tests(tests => $alias_tests, method => 'Bug.update');

my @tests;
foreach my $field (keys %$public_bug) {
  next if ($field eq 'cc' or $field eq 'description');
  my $test
    = {args => {$field => $public_bug->{$field}}, test => "Search by $field"};
  if (grep($_ eq $field, qw(alias whiteboard summary))) {
    $test->{exactly} = 1;
    $test->{bugs}    = 1;
  }
  push(@tests, $test);
}

push(
  @tests,
  (
    {
      args  => {offset => 1},
      test  => "Offset without limit fails",
      error => 'requires a limit argument',
    },

    {
      args => {alias => $private_bug->{alias}},
      test => 'Logged-out cannot find a private_bug by alias',
      bugs => 0,
    },

    {
      args => {creation_time => '19700101T00:00:00'},
      test => 'Get all bugs by creation time',
    },
    {
      args => {creation_time => '20380101T00:00:00'},
      test => 'Get no bugs, by creation time',
      bugs => 0,
    },
    {
      args => {last_change_time => '19700101T00:00:00'},
      test => 'Get all bugs by last_change_time',
    },
    {
      args => {last_change_time => '20380101T00:00:00'},
      test => 'Get no bugs by last_change_time',
      bugs => 0,
    },

    {
      args => {reporter => $config->{editbugs_user_login}},
      test => 'Search by reporter',
    },
    {args => {resolution => ''}, test => 'Search for empty resolution',},
    {
      args => {resolution => 'NO_SUCH_RESOLUTION'},
      test => 'Search for invalid resolution',
      bugs => 0,
    },
    {
      args    => {summary => substr($public_bug->{summary}, 0, 50)},
      test    => 'Search by partial summary',
      bugs    => 1,
      exactly => 1
    },
    {
      args => {summary => random_string() . ' ' . random_string()},
      test => 'Summary search that returns no results',
      bugs => 0,
    },
    {
      args => {summary => [split(/\s/, $public_bug->{summary})]},
      test => 'Summary search using multiple terms',
    },

    {
      args    => {whiteboard => substr($public_bug->{whiteboard}, 0, 50)},
      test    => 'Search by partial whiteboard',
      bugs    => 1,
      exactly => 1,
    },
    {
      args => {whiteboard => random_string(100)},
      test => 'Whiteboard search that returns no results',
      bugs => 0,
    },
    {
      args    => {whiteboard => [split(/\s/, $public_bug->{whiteboard})]},
      test    => 'Whiteboard search using multiple terms',
      bugs    => 1,
      exactly => 1,
    },

    {
      args => {
        product          => $public_bug->{product},
        component        => $public_bug->{component},
        last_change_time => '19700101T00:00:00'
      },
      test => 'Search by multiple arguments',
    },

    # Logged-in user who can see private bugs
    {
      user    => PRIVATE_BUG_USER,
      args    => {alias => [$public_bug->{alias}, $private_bug->{alias}]},
      test    => 'Search using two aliases (including one private)',
      bugs    => 2,
      exactly => 1,
    },
    {
      user => PRIVATE_BUG_USER,
      args =>
        {product => [$public_bug->{product}, $private_bug->{product}], limit => 1},
      test    => 'Limit 1',
      bugs    => 1,
      exactly => 1,
    },
    {
      user => PRIVATE_BUG_USER,
      args => {
        product => [$public_bug->{product}, $private_bug->{product}],
        limit   => 1,
        offset  => 1
      },
      test    => 'Limit 1 Offset 1',
      bugs    => 1,
      exactly => 1,
    },

    # include_fields ane exclude_fields
    {
      args => {
        id             => $public_bug->{id},
        include_fields => ['id', 'alias', 'summary', 'groups']
      },
      test => 'include_fields',
    },
    {
      args =>
        {id => $public_bug->{id}, exclude_fields => ['assigned_to', 'cf_qa_status']},
      test => 'exclude_fields'
    },
    {
      args => {
        id             => $public_bug->{id},
        include_fields => ['id', 'alias', 'summary', 'groups'],
        exclude_fields => ['summary']
      },
      test => 'exclude_fields overrides include_fields'
    },
  )
);

push(
  @tests,
  {
    args => {votes => 1},
    test => 'Search by votes',
    bugs => -1,                  # We don't care how many it returns, for now.
  }
) if $config->{test_extensions};

sub post_success {
  my ($call, $t) = @_;
  my $bugs = $call->result->{bugs};

  my $expected_count = $t->{bugs};
  $expected_count = 1 if !defined $expected_count;
  if ($expected_count) {
    my $operator = $t->{exactly} ? '==' : '>=';
    cmp_ok(scalar @$bugs,
      $operator, $expected_count, 'The right number of bugs are returned');
    unless ($t->{user} and $t->{user} eq PRIVATE_BUG_USER) {
      ok(!grep($_->{alias} && $_->{alias} eq $private_bug->{alias}, @$bugs),
        'Result does not contain the private bug');
    }

    my @include = @{$t->{args}->{include_fields} || []};
    my @exclude = @{$t->{args}->{exclude_fields} || []};
    if (@include or @exclude) {
      my @check_fields = uniq(keys %$public_bug, @include);
      foreach my $field (sort @check_fields) {
        next if $field eq 'description';
        if ( (@include and !grep { $_ eq $field } @include)
          or (@exclude and grep { $_ eq $field } @exclude))
        {
          ok(!exists $bugs->[0]->{$field}, "$field is not included")
            or diag Dumper($bugs);
        }
        else {
          ok(exists $bugs->[0]->{$field}, "$field is included");
        }
      }
    }

  }
  else {
    is(scalar @$bugs, 0, 'No bugs returned');
  }
}

foreach my $rpc (@clients) {
  $rpc->bz_run_tests(
    tests        => \@tests,
    method       => 'Bug.search',
    post_success => \&post_success
  );
}

my ($public_bug2, $public_bug3) = $clients[0]->bz_create_test_bugs();

my $depends_tests = [
    { user => 'editbugs',
      args => { ids => [ $public_bug2->{id} ], depends_on => { add => [ $public_bug3->{id}, $public_bug->{id} ] } },
      test => 'Add depends to second bug' },
    { user => 'editbugs',
      args => { ids => [ $public_bug3->{id} ], depends_on => { add => [ $public_bug->{id} ] } },
      test => 'Add depends to third bug' },
];
$clients[0]->bz_run_tests(tests => $depends_tests, method => 'Bug.update');

my @more_tests;
push(@more_tests, (
    # Should return both extra bugs.
    { args  => { f1 => 'dependson', o1 => 'equals', v1 => $public_bug->{id} },
      test  => "Can search by depends",
      bugs  => 2, exactly => 1,
    },
    # This should still return public_bug2 only, since it depends on a bug that is bug3 and a bug which isn't.
    { args  => { f1 => 'dependson', o1 => 'equals', v1 => $public_bug3->{id},
                 f2 => 'dependson', o2 => 'notequals', v2 => $public_bug3->{id} },
      test  => "Can search correctly by not depends",
      bugs  => 1, exactly => 1,
    },
    # This should return nothing, since no dependency of any bug can be both equal and unequal to the same thing.
    { args  => { f1 => 'dependson', o1 => 'equals', v1 => $public_bug3->{id},
                 f2 => 'dependson', o2 => 'notequals', v2 => $public_bug3->{id},
                 j_top => 'AND_G' },
      test  => "Contradicting depends searches return nothing.",
      bugs  => 0, exactly => 1,
    },
));

foreach my $rpc (@clients) {
    $rpc->bz_run_tests(tests => \@more_tests,
                       method => 'Bug.search', post_success => \&post_success);
}
