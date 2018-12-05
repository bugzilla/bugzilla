# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Elastic::Search;

use 5.10.1;
use Moo;
use Bugzilla::Search;
use Bugzilla::Search::Quicksearch;
use Bugzilla::Util qw(trick_taint);
use namespace::clean;

use Bugzilla::Elastic::Search::FakeCGI;


has 'quicksearch' => (is => 'ro');
has 'limit'       => (is => 'ro', predicate => 'has_limit');
has 'offset'      => (is => 'ro', predicate => 'has_offset');
has 'fields' =>
  (is => 'ro', isa => \&_arrayref_of_fields, default => sub { [] });
has 'params'             => (is => 'lazy');
has 'clause'             => (is => 'lazy');
has 'es_query'           => (is => 'lazy');
has 'search_description' => (is => 'lazy');
has 'query_time'         => (is => 'rwp');

has '_input_order' => (is => 'ro', init_arg => 'order', required => 1);
has '_order' => (is => 'lazy', init_arg => undef);
has 'invalid_order_columns' => (is => 'lazy');

with 'Bugzilla::Elastic::Role::HasClient';
with 'Bugzilla::Elastic::Role::Search';

my @SUPPORTED_FIELDS = qw(
  bug_id product component short_desc
  priority status_whiteboard bug_status resolution
  keywords alias assigned_to reporter delta_ts
  longdesc cf_crash_signature classification bug_severity
  commenter
);
my %IS_SUPPORTED_FIELD = map { $_ => 1 } @SUPPORTED_FIELDS;

$IS_SUPPORTED_FIELD{relevance} = 1;

my @NORMAL_FIELDS = qw(
  priority
  bug_severity
  bug_status
  resolution
  product
  component
  classification
  short_desc
  assigned_to
  reporter
);

my %SORT_MAP = (
  bug_id    => '_id',
  relevance => '_score',
  map { $_ => "$_.eq" } @NORMAL_FIELDS,
);

my %EQUALS_MAP = (map { $_ => "$_.eq" } @NORMAL_FIELDS,);

sub _arrayref_of_fields {
  my $f = $_;
  foreach my $field (@$f) {
    Bugzilla::Elastic::Search::UnsupportedField->throw(field => $field)
      unless $IS_SUPPORTED_FIELD{$field};
  }
}


# Future maintainer: Maybe consider removing "changeddate" from the codebase entirely.
# At some point, bugzilla tried to rename some fields
# one of these is "delta_ts" to changeddate.
# But the DB column stayed the same... and elasticsearch uses the db name
# However search likes to use the "new" name.
# for now we hack a fix in here.
my %REMAP_NAME = (changeddate => 'delta_ts',);

sub data {
  my ($self) = @_;
  my $body   = $self->es_query;
  my $result = eval {
    $self->client->search(
      index => Bugzilla::Bug->ES_INDEX,
      type  => Bugzilla::Bug->ES_TYPE,
      body  => $body,
    );
  };
  die $@ unless $result;
  $self->_set_query_time($result->{took} / 1000);

  my @fields = map { $REMAP_NAME{$_} // $_ } @{$self->fields};
  my (@ids, %hits);
  foreach my $hit (@{$result->{hits}{hits}}) {
    push @ids, $hit->{_id};
    my $source = $hit->{_source};
    $source->{relevance} = $hit->{_score};
    foreach my $val (values %$source) {
      next unless defined $val;
      trick_taint($val);
    }
    trick_taint($hit->{_id});
    if ($source) {
      $hits{$hit->{_id}} = [@$source{@fields}];
    }
    else {
      $hits{$hit->{_id}} = $hit->{_id};
    }
  }
  my $visible_ids = Bugzilla->user->visible_bugs(\@ids);

  return [map { $hits{$_} } @$visible_ids];
}

sub _valid_order {
  my ($self) = @_;

  return grep { $IS_SUPPORTED_FIELD{$_->[0]} } @{$self->_order};
}

sub order {
  my ($self) = @_;

  return map { $_->[0] } $self->_valid_order;
}

sub _quicksearch_to_params {
  my ($quicksearch) = @_;
  no warnings 'redefine';
  my $cgi = Bugzilla::Elastic::Search::FakeCGI->new;
  local *Bugzilla::cgi = sub {$cgi};
  local $Bugzilla::Search::Quicksearch::ELASTIC = 1;
  quicksearch($quicksearch);

  return $cgi->params;
}

sub _build_fields { return \@SUPPORTED_FIELDS }

sub _build__order {
  my ($self) = @_;

  my @order;
  foreach my $order (@{$self->_input_order}) {
    if ($order =~ /^(.+)\s+(asc|desc)$/i) {
      push @order, [$1, lc $2];
    }
    else {
      push @order, [$order];
    }
  }
  return \@order;
}

sub _build_invalid_order_columns {
  my ($self) = @_;

  return [map { $_->[0] }
      grep { !$IS_SUPPORTED_FIELD{$_->[0]} } @{$self->_order}];
}

sub _build_params {
  my ($self) = @_;

  return _quicksearch_to_params($self->quicksearch);
}

sub _build_clause {
  my ($self) = @_;
  my $search = Bugzilla::Search->new(params => $self->params);

  return $search->_params_to_data_structure;
}

sub _build_search_description {
  my ($self) = @_;

  return [_describe($self->clause)];
}

sub _describe {
  my ($thing) = @_;

  state $class_to_func = {
    'Bugzilla::Search::Condition' => \&_describe_condition,
    'Bugzilla::Search::Clause'    => \&_describe_clause
  };

  my $func = $class_to_func->{ref $thing} or die "nothing for $thing\n";

  return $func->($thing);
}

sub _describe_clause {
  my ($clause) = @_;

  return map { _describe($_) } @{$clause->children};
}

sub _describe_condition {
  my ($cond) = @_;

  return {
    field => $cond->field,
    type  => $cond->operator,
    value => _describe_value($cond->value)
  };
}

sub _describe_value {
  my ($val) = @_;

  return ref($val) ? join(", ", @$val) : $val;
}

sub _build_es_query {
  my ($self) = @_;
  my @extra;

  if ($self->_valid_order) {
    my @sort = map {
      my $f = $SORT_MAP{$_->[0]} // $_->[0];
      @$_ > 1 ? {$f => lc $_[1]} : $f;
    } $self->_valid_order;
    push @extra, sort => \@sort;
  }
  if ($self->has_offset) {
    push @extra, from => $self->offset;
  }
  my $max_limit = Bugzilla->params->{max_search_results};
  my $limit     = Bugzilla->params->{default_search_limit};
  if ($self->has_limit) {
    if ($self->limit) {
      my $l = $self->limit;
      $limit = $l < $max_limit ? $l : $max_limit;
    }
    else {
      $limit = $max_limit;
    }
  }
  push @extra, size => $limit;
  return {
    _source => @{$self->fields} ? \1 : \0,
    query => _query($self->clause),
    @extra,
  };
}

sub _query {
  my ($thing) = @_;
  state $class_to_func = {
    'Bugzilla::Search::Condition' => \&_query_condition,
    'Bugzilla::Search::Clause'    => \&_query_clause,
  };

  my $func = $class_to_func->{ref $thing} or die "nothing for $thing\n";

  return $func->($thing);
}

sub _query_condition {
  my ($cond) = @_;
  state $operator_to_es = {
    equals    => \&_operator_equals,
    substring => \&_operator_substring,
    anyexact  => \&_operator_anyexact,
    anywords  => \&_operator_anywords,
    allwords  => \&_operator_allwords,
  };

  my $field    = $cond->field;
  my $operator = $cond->operator;
  my $value    = $cond->value;

  if ($field eq 'resolution') {
    $value = [map { $_ eq '---' ? '' : $_ } ref $value ? @$value : $value];
  }

  unless ($IS_SUPPORTED_FIELD{$field}) {
    Bugzilla::Elastic::Search::UnsupportedField->throw(field => $field);
  }

  my $op = $operator_to_es->{$operator}
    or
    Bugzilla::Elastic::Search::UnsupportedOperator->throw(operator => $operator);

  my $result;
  if (ref $op) {
    $result = $op->($field, $value);
  }
  else {
    $result = {$op => {$field => $value}};
  }

  return $result;
}

# is equal to any of the strings
sub _operator_anyexact {
  my ($field, $value) = @_;
  my @values = ref $value ? @$value : split(/\s*,\s*/, $value);
  if (@values == 1) {
    return _operator_equals($field, $values[0]);
  }
  else {
    return {
      terms => {
        $EQUALS_MAP{$field} // $field => [map {lc} @values],
        minimum_should_match          => 1,
      },
    };
  }
}

# contains any of the words
sub _operator_anywords {
  my ($field, $value) = @_;
  return {match => {$field => {query => $value, operator => "or"}},};
}

# contains all of the words
sub _operator_allwords {
  my ($field, $value) = @_;
  return {match => {$field => {query => $value, operator => "and"}},};
}

sub _operator_equals {
  my ($field, $value) = @_;
  return {match => {$EQUALS_MAP{$field} // $field => $value,},};
}

sub _operator_substring {
  my ($field, $value) = @_;
  my $is_insider = Bugzilla->user->is_insider;

  if ($field eq 'longdesc') {
    return {
      has_child => {
        type  => 'comment',
        query => {
          bool => {
            must => [
              {match => {body => {query => $value, operator => "and"}}},
              $is_insider ? () : {term => {is_private => \0}},
            ],
          },
        },
      },
    };
  }
  elsif ($field eq 'reporter' or $field eq 'assigned_to') {
    return {prefix => {$EQUALS_MAP{$field} // $field => lc $value,}};
  }
  elsif ($field eq 'status_whiteboard' && $value =~ /[\[\]]/) {
    return {match => {$EQUALS_MAP{$field} // $field => $value,}};
  }
  else {
    return {wildcard => {$EQUALS_MAP{$field} // $field => lc "*$value*",}};
  }
}

sub _query_clause {
  my ($clause) = @_;

  state $joiner_to_func = {AND => \&_join_and, OR => \&_join_or,};

  my @children = grep { !$_->isa('Bugzilla::Search::Clause') || @{$_->children} }
    @{$clause->children};
  if (@children == 1) {
    return _query($children[0]);
  }

  return $joiner_to_func->{$clause->joiner}->([map { _query($_) } @children]);
}

sub _join_and {
  my ($children) = @_;
  return {bool => {must => $children}},;
}

sub _join_or {
  my ($children) = @_;
  return {bool => {should => $children}};
}

# Exceptions
BEGIN {

  package Bugzilla::Elastic::Search::Redirect;
  use Moo;

  with 'Throwable';

  has 'redirect_args' => (is => 'ro', required => 1);

  package Bugzilla::Elastic::Search::UnsupportedField;
  use Moo;
  use overload
    q{""}    => sub { "Unsupported field: ", $_[0]->field },
    fallback => 1;

  with 'Throwable';

  has 'field' => (is => 'ro', required => 1);


  package Bugzilla::Elastic::Search::UnsupportedOperator;
  use Moo;

  with 'Throwable';

  has 'operator' => (is => 'ro', required => 1);
}

1;
