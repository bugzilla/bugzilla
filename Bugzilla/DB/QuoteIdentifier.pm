# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::DB::QuoteIdentifier;

use 5.10.1;
use Moo;

has 'db' =>
  (is => 'ro', required => 1, handles => [qw[quote quote_identifier]]);

has sql_identifier_quote_char => (is => 'ro', required => 1);

extends 'Parser::MGC';

sub _build_sql_identifier_quote_char {
  my ($self) = @_;

  return $self->db->dbh->get_info(29);
}

sub FOREIGNBUILDARGS {
  my ($self, %options) = @_;

  $options{patterns}{string_delim} = qr/[']/;

  return %options;
}

sub parse {
  my ($self) = @_;
  my $distinct = $self->maybe_expect(qr/DISTINCT/i);

  ["select", $distinct, $self->list_of(",", sub { $self->parse_selection })];
}

sub parse_selection {
  my ($self) = @_;
  my $expr   = $self->parse_expr;
  my $alias  = $self->maybe(sub {
    $self->generic_token('as', qr/AS/i);
    $self->parse_ident;
  });

  defined($alias) ? ["alias", $alias, $expr] : $expr;
}

sub parse_args {
  my ($self) = @_;

  $self->list_of(",", sub { $self->parse_expr });
}

sub parse_expr {
  my ($self) = @_;

  $self->parse_expr_10();
}

sub parse_expr_10 {
  my ($self) = @_;

  $self->any_of(
    sub { $self->parse_case },
    sub {
      my $val     = $self->parse_expr_9;
      my $min_max = $self->maybe(sub {
        $self->expect(qr/BETWEEN/i);
        $self->commit;
        my $min = $self->parse_expr_9;
        $self->expect(qr/AND/i);
        $self->commit;
        my $max = $self->parse_expr_9;
        [$min, $max];
      });
      defined($min_max) ? ["between", $val, @$min_max] : $val;
    }
  );
}

sub parse_case {
  my ($self) = @_;

  $self->committed_scope_of(qr/CASE/i, 'parse_case_body', qr/END/i);
}

sub parse_case_body {
  my ($self) = @_;

  [
    "case",
    $self->parse_expr_9,
    $self->sequence_of(sub {
      $self->any_of(
        sub {
          $self->expect(qr/WHEN/i);
          $self->commit;
          my $compare = $self->parse_expr_9;
          $self->expect(qr/THEN/i);
          $self->commit;
          my $result = $self->parse_expr_9;
          ["when", $compare, $result];
        },
        sub {
          $self->expect(qr/ELSE/i);
          $self->commit;
          my $result = $self->parse_expr_9;
          ["else", $result];
        }
      );
    })
  ];
}

sub parse_expr_9 {
  my ($self) = @_;

  $self->parse_operators(
    'parse_expr_8',
    qw( = <=> >= > <= < <> != ),
    qr/IS(?:\s+NOT)?/i,
    qr/(?:NOT\s+)?LIKE/i,
    qr/(?:NOT\s+)?REGEXP/i,
    sub {
      my ($ref_val) = @_;
      my $type = $self->maybe_expect(qr/NOT/i) ? "NOT IN" : "IN";
      $self->expect(qr/IN/i);
      $self->commit;
      my $in_args = $self->committed_scope_of('(', 'parse_args', ')');
      $$ref_val = ["inop", $type, $$ref_val, $in_args];
    },
  );
}

sub parse_expr_8 {
  my ($self) = @_;

  $self->parse_operators('parse_expr_7', qw( | ));
}

sub parse_expr_7 {
  my ($self) = @_;

  $self->parse_operators('parse_expr_6', qw( & ));
}

sub parse_expr_6 {
  my ($self) = @_;

  $self->parse_operators('parse_expr_5', qw( << >> ));
}

sub parse_expr_5 {
  my ($self) = @_;

  $self->parse_operators('parse_expr_4', qw( + - ));
}

sub parse_expr_4 {
  my ($self) = @_;

  $self->parse_operators('parse_expr_3', qw( * / % DIV MOD ));
}

sub parse_expr_3 {
  my ($self) = @_;

  $self->parse_operators('parse_expr_1', qw( ^ ));
}

sub parse_expr_1 {
  my ($self) = @_;

  $self->any_of(
    sub {
      $self->expect(qr/INTERVAL/i);
      $self->commit;
      my $expr = $self->parse_expr_0;
      $self->commit;
      my $unit = $self->parse_unit;
      ["interval", $expr, $unit];
    },
    sub { $self->parse_expr_0 },
  );
}

sub parse_unit {
  my ($self) = @_;
  my @units = qw(
    MICROSECOND SECOND MINUTE HOUR DAY WEEK MONTH QUARTER YEAR
    SECOND_MICROSECOND MINUTE_MICROSECOND MINUTE_SECOND HOUR_MICROSECOND
    HOUR_SECOND HOUR_MINUTE DAY_MICROSECOND DAY_SECOND DAY_MINUTE DAY_HOUR
    YEAR_MONTH
  );

  $self->token_kw(@units);
}

sub parse_expr_0 {
  my ($self) = @_;

  $self->any_of(
    sub { ["parens", $self->committed_scope_of('(', 'parse_expr', ')')]; },
    sub { $self->expect(qr/NULL/i);         ["const", "NULL"] },
    sub { $self->expect(qr/TRUE/i);         ["const", "TRUE"] },
    sub { $self->expect(qr/FALSE/i);        ["const", "FALSE"] },
    sub { $self->expect(qr/CURRENT_DATE/i); ["const", "CURRENT_DATE"] },
    sub { $self->expect('?');               ["const", "?"] },
    sub { $self->expect('!');               ["unop",  "!", $self->parse_expr_0] },
    sub { $self->expect('-');               ["unop",  "-", $self->parse_expr_0] },
    sub { $self->expect('~');               ["unop",  "~", $self->parse_expr_0] },
    sub { $self->token_number },
    sub { $self->parse_count },
    sub { $self->parse_cast },
    sub { $self->parse_call },
    sub { ["ident", $self->parse_qualified_ident] },
    sub { ["ident", $self->parse_ident] },
    sub { ["quote", $self->token_string] },
  );
}

sub parse_count {
  my ($self) = @_;

  $self->expect(qr/COUNT/i);
  $self->committed_scope_of(
    '(',
    sub {
      my ($self) = @_;
      $self->any_of(
        sub { $self->expect('*'); $self->commit; ['count', '*'] },
        sub {
          $self->expect(qr/DISTINCT/i);
          $self->commit;
          ['count', 'distinct', $self->parse_args];
        },
        sub { ["call", "COUNT", $self->parse_args] },
      );
    },
    ')'
  );
}

sub parse_cast {
  my ($self) = @_;

  $self->expect(qr/CAST/i);
  $self->committed_scope_of(
    '(',
    sub {
      my ($self) = @_;
      my $expr = $self->parse_expr;
      $self->expect(qr/AS/i);
      my $type = $self->token_ident;
      ["cast", $expr, $type];
    },
    ')'
  );
}

sub parse_call {
  my ($self) = @_;
  my $ident = $self->token_ident;

  ["call", $ident, $self->committed_scope_of('(', 'parse_args', ')')];
}

sub parse_qualified_ident {
  my ($self) = @_;
  my $table = $self->parse_ident;
  $self->expect('.');
  my $column = $self->parse_ident;

  ($table, $column);
}

sub parse_ident {
  my ($self) = @_;

  $self->any_of(
    sub { $self->token_ident },
    sub {
      my $char = $self->sql_identifier_quote_char;
      my (undef, $id) = $self->expect(qr/\Q$char\E\s*([^$char]+?)\s*\Q$char\E/);
      $id;
    },
  );
}

sub parse_operators {
  my ($self, $method, @operators) = @_;
  my $val = $self->$method;
  my @ops;

  foreach my $op (@operators) {
    if (ref $op eq 'CODE') {
      push @ops, sub {
        $op->(\$val);
        1;
      };
    }
    else {
      push @ops, sub {
        $op = $self->expect($op);
        $self->commit;
        $val = ["binop", uc $op, $val, $self->$method];
        1;
      }
    }
  }
  push @ops, sub {0};

  for (;;) {
    $self->any_of(@ops) or last;
  }

  return $val;
}

sub to_string {
  my ($self, $node) = @_;
  if (ref $node) {
    my $method = '_to_string_' . shift @$node;
    $self->$method(@$node);
  }
  else {
    return $node;
  }
}

sub _to_string_select {
  my ($self, $distinct, $selection) = @_;
  my $prefix = $distinct ? uc "$distinct " : "";

  $prefix . join(', ', map { $self->to_string($_) } @$selection);
}

sub _to_string_ident {
  my $self = shift;
  if (@_ == 2) {
    $self->quote_identifier($_[0]) . "." . $self->quote_identifier($_[1]);
  }
  else {
    $self->quote_identifier($_[0]);
  }
}

sub _to_string_const {
  my ($self, $const) = @_;

  return $const;
}

sub _to_string_count {
  my ($self, $type, $args) = @_;
  if ($type eq '*') {
    return 'COUNT(*)';
  }
  elsif ($type eq 'distinct') {
    sprintf "COUNT(DISTINCT %s)", $type,
      join(", ", map { $self->to_string($_) } @$args);
  }
  else {
    die "unsupported type of count syntax";
  }
}

sub _to_string_cast {
  my ($self, $expr, $type) = @_;

  sprintf "CAST(%s AS %s)", $self->to_string($expr), $type;
}

sub _to_string_call {
  my ($self, $name, $args) = @_;

  sprintf "%s(%s)", $name, join(", ", map { $self->to_string($_) } @$args);
}

sub _to_string_quote {
  my ($self, $str) = @_;

  $self->quote($str);
}

sub _to_string_parens {
  my ($self, $expr) = @_;

  sprintf "(%s)", $self->to_string($expr);
}

sub _to_string_binop {
  my ($self, $op, $left, $right) = @_;
  $self->to_string($left) . " $op " . $self->to_string($right);
}

sub _to_string_unop {
  my ($self, $op, $expr) = @_;
  sprintf "%s %s", $op, $self->to_string($expr);
}

sub _to_string_interval {
  my ($self, $expr, $unit) = @_;
  sprintf "INTERVAL %s %s", $self->to_string($expr), $unit;
}

sub _to_string_alias {
  my ($self, $alias, $expr) = @_;

  sprintf "%s AS %s", $self->to_string($expr), $self->quote_identifier($alias);
}

sub _to_string_inop {
  my ($self, $op, $expr, $exprs) = @_;
  sprintf "%s %s (%s)", $self->to_string($expr), uc $op,
    join(", ", map { $self->to_string($_) } @$exprs);
}

sub _to_string_case {
  my ($self, $value, $conds) = @_;

  'CASE '
    . $self->to_string($value) . ' '
    . join(' ', map { $self->to_string($_) } @$conds) . ' END';
}

sub _to_string_when {
  my ($self, $compare, $result) = @_;

  'WHEN ' . $self->to_string($compare) . ' THEN ' . $self->to_string($result);
}

sub _to_string_else {
  my ($self, $result) = @_;

  'ELSE ' . $self->to_string($result);
}

sub _to_string_between {
  my ($self, $val, $min, $max) = @_;

  sprintf "%s BETWEEN %s AND %s", $self->to_string($val), $self->to_string($min),
    $self->to_string($max);
}

1;

__END__

=head1 NAME

Bugzilla::DB::QuoteIdentifier

=head1 SYNOPSIS

  my %q;
  tie %q, 'Bugzilla::DB::QuoteIdentifier', db => Bugzilla->dbh;

  is("this is $q{something}", 'this is ' . Bugzilla->dbh->quote_identifier('something'));

=head1 DESCRIPTION

Bugzilla has many strings with bare sql column names or table names. Sometimes,
as in the case of MySQL 8, formerly unreserved keywords can become reserved.

This module provides a shortcut for quoting identifiers in strings by way of overloading a hash
so that we can easily call C<quote_identifier> inside double-quoted strings.

=cut

