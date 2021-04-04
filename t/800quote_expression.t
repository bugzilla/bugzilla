#!/usr/bin/env perl
use strict;
use warnings;
use 5.10.1;
use Test2::V0;
use File::Spec::Functions qw(catdir);
use File::Basename qw(dirname);
use Package::Stash;

use lib catdir(dirname(__FILE__), '..');

use ok 'Bugzilla::DB::Mysql';
use ok 'Bugzilla::DB::Pg';
use ok 'Bugzilla::DB::Sqlite';
use ok 'Bugzilla::DB';
use ok 'Bugzilla::DB::QuoteExpression';

my %sql_method_test = (
  sql_iposition => sub {
    my ($dbh, $parse) = @_;
    ok(lives { $parse->($dbh->sql_iposition('?', 'login_name')) },
      "sql_iposition is parseable")
      or note($@);
  },
  sql_position => sub {
    my ($dbh, $parse) = @_;
    ok(lives { $parse->($dbh->sql_position(q{'\n'}, 'thetext') . q{ > 81 }) },
      "sql_position is parseable")
      or note($@);
  },
  sql_string_concat => sub {
    my ($dbh, $parse) = @_;
    ok(
      lives {
        $parse->($dbh->sql_string_concat('map_flagtypes.name', 'map_flags.status'))
      },
      "sql_string_concat is parseable"
    ) or note($@);
  },
  sql_date_format => sub {
    my ($dbh, $parse) = @_;
    ok(lives { $parse->($dbh->sql_date_format('bugs.deadline', '%Y-%m-%d')) },
      "sql_date_format is parseable")
      or note($@);
  },
  sql_date_math => sub {
    my ($dbh, $parse) = @_;
    ok(lives { $parse->($dbh->sql_date_math('NOW()', '-', 30, 'MINUTE')) },
      "sql_date_math NOW() - 30 MINUTE")
      or note($@);
  },
  sql_to_days => sub {
    my ($dbh, $parse) = @_;
    ok(lives { $parse->($dbh->sql_to_days('bugs_activity.bug_when')) },
      "sql_to_days is parseable")
      or note($@);
  },
  sql_from_days => sub {
    my ($dbh, $parse) = @_;
    ok(lives { $parse->($dbh->sql_from_days(42)) }, "sql_from_days is parseable")
      or note($@);
  },
  sql_regexp => sub {
    my ($dbh, $parse) = @_;
    ok(lives { $parse->($dbh->sql_regexp('profiles.login_name', q{'@'})) },
      "sql_regexp is parseable")
      or note($@);
  },
  sql_not_regexp => sub {
    my ($dbh, $parse) = @_;
    ok(lives { $parse->($dbh->sql_not_regexp('profiles.login_name', q{'@'})) },
      "sql_not_regexp is parseable")
      or note($@);
  },
  sql_istring => sub {
    my ($dbh, $parse) = @_;
    ok(lives { $parse->($dbh->sql_istring('profiles.login_name')) },
      "sql_istring is parseable")
      or note($@);
  },
  sql_limit => sub {
    note("sql_limit is not expression, not tested.");
  },
  sql_group_by => sub {
    note("sql_group_by is not expression, not tested.");
  },
  sql_group_concat => sub {
    my ($dbh, $parse) = @_;
    ok(
      lives { $parse->($dbh->sql_group_concat('DISTINCT map_dependson.dependson')) },
      "sql_group_concat is parseable (example 1)"
    ) or note($@);
    ok(lives { $parse->($dbh->sql_group_concat('tag', "','")) },
      "sql_group_concat is parseable (example 2)")
      or note($@);
    my $newline = $dbh->quote("\n");
    ok(lives { $parse->($dbh->sql_group_concat('longdescs.thetext', $newline, 0)) },
      "sql_group_concat is parseable (example 3)")
      or note($@);
  },
  sql_fulltext_search => sub {
    my ($dbh, $parse) = @_;
    my $word = 'mysql';
    ok(
      lives {
        $parse->($dbh->sql_fulltext_search('bugs_fulltext.short_desc', $word))
      },
      "sql_fulltext_search (word)"
    ) or note($@);
    my $phrase = 'mysql | sucks (use mariadb)';
    ok(
      lives {
        $parse->($dbh->sql_fulltext_search('bugs_fulltext.short_desc', $phrase))
      },
      "sql_fulltext_search (phrase)"
    ) or note($@);
  },
);


my $mysql_stash = Package::Stash->new('Bugzilla::DB::Mysql');
my %quote       = (
  qq{\n}   => q{\n},
  qq{\t}   => q{\t},
  qq{\r}   => q{\r},
  qq{'}    => q{\'},
  qq{\\\\} => q{\\\\},
);
my $escapes = join('', keys %quote);
my $mysql_mock = mock 'Bugzilla::DB::Mysql' => (
  add_constructor => ['new_fake' => 'hash'],
  override        => [
    bz_check_regexp => sub { },
    quote           => sub {
      my (undef, $s) = @_;
      my $escapes = join('', keys %quote);
      $s =~ s/([$escapes])/$quote{$1}/ges;
      return "'$s'";
    },
    quote_identifier => sub {
      my (undef, @id) = @_;
      return join(".", map {"`$_`"} @id);
    },
  ]
);
my $mysql       = Bugzilla::DB::Mysql->new_fake;
my $mysql_parse = sub {
  state $parser = Bugzilla::DB::QuoteExpression->new(
    db                        => $mysql,
    sql_identifier_quote_char => '`'
  );
  my $ast = $parser->from_string($_[0]);
  my $sql = $parser->to_string($ast);
  note("IN:  $_[0]\nOUT: $sql\n");

  #use Data::Dumper;
  #note("AST: " . Dumper($ast));
  $sql;
};

my @sql_methods = sort grep {/^sql_/} $mysql_stash->list_all_symbols('CODE');

foreach my $method (@sql_methods) {
  if (my $test = $sql_method_test{$method}) {
    $test->($mysql, $mysql_parse);
  }
  else {
    fail("No test for $method");
  }
}

done_testing;
