# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Report::SecurityRisk;

use 5.10.1;
use Moo;
use MooX::StrictConstructor;

use Bugzilla::Error;
use Bugzilla::Status qw(is_open_state);
use Bugzilla::Util qw(datetime_from diff_arrays);
use Bugzilla;

use Chart::Clicker;
use Chart::Clicker::Axis::DateTime;
use Chart::Clicker::Data::Series;
use Chart::Clicker::Data::DataSet;
use Chart::Clicker::Renderer::Point;
use Chart::Clicker::Renderer::StackedArea;

use DateTime;
use JSON::PP::Boolean;
use List::Util qw(any first sum uniq);
use Mojo::File qw(tempfile);
use POSIX qw(ceil);
use Type::Utils;
use Types::Standard qw(:types);

my $DateTime = class_type {class => 'DateTime'};
my $JSONBool = class_type {class => 'JSON::PP::Boolean'};

has 'start_date' => (is => 'ro', required => 1, isa => $DateTime);

has 'end_date' => (is => 'ro', required => 1, isa => $DateTime);

# The teams are loaded from an admin parameter containing JSON, e.g.:
# {
#   "Plugins": {
#     "Core": {
#         "all_components": false,
#         "prefixed_components": ["Plugin"],
#         "named_components": [
#             "Plug-ins"
#         ]
#     },
#     "Plugins": { "all_components": true },
#     "External Software Affecting Firefox": { "all_components": true }
#   },
#   ...
# }
# This will create a new team ("Plugins") which groups bugs in the following components:
# - All components in the Core product that start with "Plugin" (e.g. Plugin:FlashPlayer)
# - The single "Plug-ins" component in the Core product.
# - All components in the Plugins _product_.
# - All components in the External Software Affecting Firefox product.
has 'teams' => (
  is       => 'ro',
  required => 1,
  isa      => HashRef [
    HashRef [
      Dict [
        all_components      => $JSONBool,
        prefixed_components => Optional [ArrayRef [Str]],
        named_components    => Optional [ArrayRef [Str]],
      ],
    ],
  ],
);

has 'sec_keywords' => (is => 'ro', required => 1, isa => ArrayRef [Str],);

has 'products' => (is => 'lazy', isa => ArrayRef [Str],);

has 'missing_products' => (is => 'lazy', isa => ArrayRef [Str],);

has 'missing_components' => (is => 'lazy', isa => ArrayRef [Str],);

has 'initial_bug_ids' => (is => 'lazy', isa => ArrayRef [Int],);

has 'initial_bugs' => (
  is  => 'lazy',
  isa => HashRef [
    Dict [
      id         => Int,
      product    => Str,
      component  => Str,
      team       => Maybe [Str],
      sec_level  => Str,
      status     => Str,
      is_stalled => Bool,
      is_open    => Bool,
      created_at => $DateTime,
    ],
  ],
);

has 'check_open_state' =>
  (is => 'ro', isa => CodeRef, default => sub { return \&is_open_state; },);

has 'very_old_days' => (is => 'ro', isa => Int, default => 45);

has 'events' => (
  is  => 'lazy',
  isa => ArrayRef [
    Dict [
      bug_id     => Int,
      bug_when   => $DateTime,
      field_name => Enum [qw(bug_status keywords)],
      removed    => Str,
      added      => Str,
    ],
  ],
);

has 'results' => (
  is  => 'lazy',
  isa => ArrayRef [
    Dict [
      date         => $DateTime,
      bugs_by_team => HashRef [
        Dict [open => ArrayRef [Int], closed => ArrayRef [Int], very_old_bugs => ArrayRef [Int]]
      ],
      bugs_by_sec_keyword => HashRef [
        Dict [open => ArrayRef [Int], closed => ArrayRef [Int], very_old_bugs => ArrayRef [Int]]
      ],
    ],
  ],
);

has 'deltas' => (
  is  => 'lazy',
  isa => Dict [
    by_sec_keyword =>
      HashRef [Dict [added => ArrayRef [Int], closed => ArrayRef [Int],],],
    by_team => HashRef [Dict [added => ArrayRef [Int], closed => ArrayRef [Int],],],
  ],
);

has 'graphs' => (
  is  => 'lazy',
  isa => Dict [
    bugs_by_sec_keyword_count => Object,
    bugs_by_sec_keyword_age   => Object,
    bugs_by_team_age          => Object,
  ],
);

sub _build_products {
  my ($self) = @_;
  my @products = ();
  foreach my $team (values %{$self->teams}) {
    foreach my $product (keys %$team) {
      push @products, $product;
    }
  }
  @products = uniq @products;
  return \@products;
}

sub _build_missing_products {
  my ($self) = @_;
  my $dbh = Bugzilla->dbh;
  my @products = map { $dbh->quote($_) } @{$self->products};
  my $query = qq{
        SELECT
            name
        FROM
            products
         WHERE
            @{[$dbh->sql_in('products.name', \@products)]}
    };
  my $found_products = Bugzilla->dbh->selectcol_arrayref($query);
  return (diff_arrays($self->products, $found_products))[0];
}

sub _build_missing_components {
  my ($self) = @_;
  my $dbh = Bugzilla->dbh;
  my $products           = join ', ', map { $dbh->quote($_) } @{$self->products};
  my @named_components   = ();
  my @missing_components = ();
  foreach my $team (values %{$self->teams}) {
    foreach my $product (keys %$team) {
      if (exists $team->{$product}->{named_components}) {
        foreach my $component (@{$team->{$product}->{named_components}}) {
          push @named_components, [$product, $component];
        }
      }
    }
  }

  my @components = map { $dbh->quote($_->[1]) } @named_components;
  my $query = qq{
      SELECT
          product.name,
          component.name
      FROM
          components AS component
          JOIN products AS product ON component.product_id = product.id
      WHERE
          @{[$dbh->sql_in('component.name', \@components)]}
  };
  my $found_components = Bugzilla->dbh->selectall_arrayref($query);

  foreach my $named_component (@named_components) {
    my $found = 0;
    foreach my $found_component (@$found_components) {
      if ( lc $named_component->[0] eq lc $found_component->[0]
        && lc $named_component->[1] eq lc $found_component->[1])
      {
        $found = 1;
        last;
      }
    }
    push @missing_components, "$named_component->[0]::$named_component->[1]"
      if !$found;
  }
  return \@missing_components;
}

sub _build_initial_bug_ids {

# TODO: Handle changes in product (e.g. gravyarding) by searching the events table
# for changes to the 'product' field where one of $self->products is found in
# the 'removed' field, add the related bug id to the list of initial bugs.
  my ($self) = @_;
  my $dbh = Bugzilla->dbh;
  my $products     = join ', ', map { $dbh->quote($_) } @{$self->products};
  my $sec_keywords = join ', ', map { $dbh->quote($_) } @{$self->sec_keywords};
  my $query        = qq{
        SELECT
            bug_id
        FROM
            bugs AS bug
            JOIN products AS product ON bug.product_id = product.id
            JOIN components AS component ON bug.component_id = component.id
            JOIN keywords USING (bug_id)
            JOIN keyworddefs AS keyword ON keyword.id = keywords.keywordid
         WHERE
            keyword.name IN ($sec_keywords)
            AND product.name IN ($products)
    };
  return Bugzilla->dbh->selectcol_arrayref($query);
}

sub _build_initial_bugs {
  my ($self)    = @_;
  my $bugs      = {};
  my $bugs_list = Bugzilla::Bug->new_from_list($self->initial_bug_ids);
  for my $bug (@$bugs_list) {
    my $is_stalled = grep { lc($_->name) eq 'stalled' } @{$bug->keyword_objects};
    $bugs->{$bug->id} = {
      id        => $bug->id,
      product   => $bug->product,
      component => $bug->component,
      team      => $self->_find_team($bug->product, $bug->component),
      sec_level => (

        # Select the first keyword matching one of the target keywords
        # (of which there _should_ only be one found anyway).
        first {
          my $x = $_;
          grep { lc($_) eq lc($x->name) } @{$self->sec_keywords}
        }
        @{$bug->keyword_objects}
      )->name,
      status     => $bug->status->name,
      is_stalled => scalar $is_stalled,
      is_open    => $self->_is_bug_open($bug->status->name, scalar $is_stalled),
      created_at => datetime_from($bug->creation_ts),
    };
  }
  return $bugs;
}

sub _build_events {
  my ($self) = @_;
  return [] if !(@{$self->initial_bug_ids});
  my $bug_ids    = join ', ', @{$self->initial_bug_ids};
  my $start_date = $self->start_date->strftime('%Y-%m-%d %H:%M:%S');
  my $query      = qq{
        SELECT
            bug_id,
            bug_when,
            field.name AS field_name,
            CONCAT(removed) AS removed,
            CONCAT(added) AS added
        FROM
            bugs_activity
            JOIN fielddefs AS field ON fieldid = field.id
            JOIN bugs AS bug USING (bug_id)
        WHERE
            bug_id IN ($bug_ids)
            AND field.name IN ('keywords' , 'bug_status')
            AND bug_when >= '$start_date'
        GROUP BY bug_id , bug_when , field.name
    };
  # Don't use selectall_hashref as it only gets the latest event each bug.
  my $result = Bugzilla->dbh->selectall_arrayref($query);
  my $type   = ArrayRef [Tuple [Int, Str, Str, Str, Str]];
  $type->assert_valid($result);

  my @events = map {
    +{
      'bug_id'     => $_->[0],
      'bug_when'   => datetime_from($_->[1]),
      'field_name' => $_->[2],
      'removed'    => $_->[3],
      'added'      => $_->[4],
    }
  } @$result;

  # We sort by reverse chronological order instead of ORDER BY
  # since values %hash doesn't guarantee any order.
  @events = sort { $b->{bug_when} cmp $a->{bug_when} } @events;
  return \@events;
}

sub _build_results {
  my ($self)  = @_;
  my $e       = 0;
  my $bugs    = $self->initial_bugs;
  my @results = ();

# We must generate a report for each week in the target time interval, regardless of
# whether anything changed. The for loop here ensures that we do so.
  for (
    my $report_date = $self->end_date->clone();
    $report_date >= $self->start_date;
    $report_date->subtract(weeks => 1)
    )
  {

# We rewind events while there are still events existing which occurred after the start
# of the report week. The bugs will reflect a snapshot of how they were at the start of the week.
# $self->events is ordered reverse chronologically, so the end of the array is the earliest event.
    while ($e < @{$self->events}
      && (@{$self->events}[$e])->{bug_when} > $report_date)
    {
      my $event = @{$self->events}[$e];
      my $bug   = $bugs->{$event->{bug_id}};


      # Undo bug status changes
      if ($event->{field_name} eq 'bug_status') {
        $bug->{status} = $event->{removed};
        $bug->{is_open} = $self->_is_bug_open($bug->{status}, $bug->{is_stalled});
      }

      # Undo sec keyword changes
      if ($event->{field_name} eq 'keywords') {
        my $bug_sec_level = $bug->{sec_level} // '';
        if ($event->{added} =~ /\b\Q$bug_sec_level\E\b/) {

          # If the currently set sec level was added in this event, remove it.
          $bug->{sec_level} = undef;
        }
        if ($event->{removed}) {

          # If a target sec keyword was removed, add the first one back.
          my $removed_sec = first { $event->{removed} =~ /\b\Q$_\E\b/ }
          @{$self->sec_keywords};
          $bug->{sec_level} = $removed_sec if ($removed_sec);
        }
      }

      # Undo stalled keyword changes
      if ($event->{field_name} eq 'keywords') {
        if ($event->{added} =~ /\b\stalled\b/) {

          # If the stalled keyword was added in this event, remove it:
          $bug->{is_stalled} = 0;
        }
        if ($event->{removed} =~ /\b\stalled\b/) {

          # If the stalled keyword was removed in this event, add it:
          $bug->{is_stalled} = 1;
        }
        $bug->{is_open} = $self->_is_bug_open($bug->{status}, $bug->{is_stalled});
      }

      $e++;
    }

    # Remove uncreated bugs
    foreach my $bug_key (keys %$bugs) {
      if ($bugs->{$bug_key}->{created_at} > $report_date) {
        delete $bugs->{$bug_key};
      }
    }

    # Report!
    my $date_snapshot = $report_date->clone();
    my @bugs_snapshot = values %$bugs;
    my $result        = {
      date         => $date_snapshot,
      bugs_by_team => $self->_bugs_by_team($date_snapshot, @bugs_snapshot),
      bugs_by_sec_keyword =>
        $self->_bugs_by_sec_keyword($date_snapshot, @bugs_snapshot),
    };
    push @results, $result;
  }

  return [reverse @results];
}

sub _build_graphs {
  my ($self) = @_;
  my $graphs = {};
  my $data   = [
    {
      id    => 'bugs_by_sec_keyword_count',
      title => sprintf(
        'Open security bugs by severity (%s to %s)',
        $self->start_date->ymd,
        $self->end_date->ymd
      ),
      range_label => 'Open Bugs Count',
      datasets    => [
        map {
          my $keyword = $_;
          {
            name   => $_,
            keys   => [map { $_->{date}->epoch } @{$self->results}],
            values => [
              map { scalar @{$_->{bugs_by_sec_keyword}->{$keyword}->{open}} }
                @{$self->results}
            ],
          }
        } @{$self->sec_keywords}
      ],
      renderer   => Chart::Clicker::Renderer::StackedArea->new(opacity => .6),
      image_file => tempfile(SUFFIX => '.png'),
    },
    {
      id    => 'bugs_by_sec_keyword_age',
      title => sprintf(
        '# of open security bugs older than 45 days by severity (%s to %s)',
        $self->start_date->ymd,
        $self->end_date->ymd
      ),
      range_label => 'Bug Count',
      datasets    => [
        map {
          my $keyword = $_;
          {
            name   => $_,
            keys   => [map { $_->{date}->epoch } @{$self->results}],
            values => [
              map {
                scalar @{$_->{bugs_by_sec_keyword}->{$keyword}->{very_old_bugs}}
              } @{$self->results}
            ],
          }
        } @{$self->sec_keywords}
      ],
      image_file => tempfile(SUFFIX => '.png'),
    },
    {
      id    => 'bugs_by_team_age',
      title => sprintf(
        '# of open security bugs older than 45 days by team (%s to %s)',
        $self->start_date->ymd,
        $self->end_date->ymd
      ),
      range_label => 'Bug Count',
      datasets    => [
        map {
          my $team = $_;
          {
            name => $_,
            keys => [map { $_->{date}->epoch } @{$self->results}],
            values => [
              map {
                scalar @{$_->{bugs_by_team}->{$team}->{very_old_bugs}}
              }@{$self->results}
            ],
          }
        } keys %{$self->teams}
      ],
      image_file => tempfile(SUFFIX => '.png'),
    },
  ];

  foreach my $datum (@$data) {
    my $cc = Chart::Clicker->new;
    $cc->title->text($datum->{title});
    $cc->title->font->size(14);
    $cc->title->padding->bottom(5);
    $cc->title->padding->top(5);
    foreach my $dataset (@{$datum->{datasets}}) {
      my $series = Chart::Clicker::Data::Series->new(
        name   => $dataset->{name},
        values => $dataset->{values},
        keys   => $dataset->{keys},
      );
      my $ds = Chart::Clicker::Data::DataSet->new(series => [$series]);
      $cc->add_to_datasets($ds);
    }
    my $ctx = $cc->get_context('default');
    $ctx->renderer($datum->{renderer}) if exists $datum->{renderer};
    $ctx->range_axis->label($datum->{range_label});
    $ctx->domain_axis(Chart::Clicker::Axis::DateTime->new(
      position    => 'bottom',
      orientation => 'horizontal',
      format      => "%m/%d",
    ));
    $cc->write_output($datum->{image_file});
    $graphs->{$datum->{id}} = $datum->{image_file};
  }

  return $graphs;
}

sub _build_deltas {
  my ($self) = @_;
  my @teams = keys %{$self->teams};
  my $deltas = {by_team => {}, by_sec_keyword => {}};
  my $data = [
    {domain => \@teams, results_key => 'bugs_by_team', deltas_key => 'by_team',},
    {
      domain      => $self->sec_keywords,
      results_key => 'bugs_by_sec_keyword',
      deltas_key  => 'by_sec_keyword',
    }
  ];

  foreach my $datum (@$data) {
    foreach my $item (@{$datum->{domain}}) {
      my $current_result = $self->results->[-1]->{$datum->{results_key}}->{$item};
      my $last_result    = $self->results->[-2]->{$datum->{results_key}}->{$item};

      my @all_bugs_this_week
        = (@{$current_result->{open}}, @{$current_result->{closed}});
      my @all_bugs_last_week = (@{$last_result->{open}}, @{$last_result->{closed}});

      my $added_delta = (diff_arrays(\@all_bugs_this_week, \@all_bugs_last_week))[0];
      my $closed_delta
        = (diff_arrays($current_result->{closed}, $last_result->{closed}))[0];

      $deltas->{$datum->{deltas_key}}->{$item}
        = {added => $added_delta, closed => $closed_delta};
    }
  }
  return $deltas;
}

sub _bugs_by_team {
  my ($self, $report_date, @bugs) = @_;
  my $result = {};
  my $groups = {};
  foreach my $team (keys %{$self->teams}) {
    $groups->{$team} = [];
  }
  foreach my $bug (@bugs) {

    # We skip over bugs with no sec level which can happen during event rewinding.
    # We also skip over bugs that don't fall into one of the specified teams.
    if (defined $bug->{sec_level} && defined $bug->{team}) {
      push @{$groups->{$bug->{team}}}, $bug;
    }
  }
  foreach my $team (keys %{$self->teams}) {
    my @open   = map { $_->{id} } grep { ($_->{is_open}) } @{$groups->{$team}};
    my @closed = map { $_->{id} } grep { !($_->{is_open}) } @{$groups->{$team}};
    my @very_old_bugs   = map { $_->{id} } grep {
      $_->{created_at}->subtract_datetime_absolute($report_date)->seconds / 86_400 >= $self->very_old_days;
    } grep { ($_->{is_open}) } @{$groups->{$team}};
    $result->{$team} = {
      open            => [ sort @open ],
      closed          => [ sort @closed ],
      very_old_bugs   => [ sort @very_old_bugs ],
    };
  }

  return $result;
}

sub _bugs_by_sec_keyword {
  my ($self, $report_date, @bugs) = @_;
  my $result = {};
  my $groups = {};
  foreach my $sec_keyword (@{$self->sec_keywords}) {
    $groups->{$sec_keyword} = [];
  }
  foreach my $bug (@bugs) {

    # We skip over bugs with no sec level which can happen during event rewinding.
    if (defined $bug->{sec_level}) {
      push @{$groups->{$bug->{sec_level}}}, $bug;
    }
  }
  foreach my $sec_keyword (@{$self->sec_keywords}) {
    my @open = map { $_->{id} } grep { ($_->{is_open}) } @{$groups->{$sec_keyword}};
    my @closed
      = map { $_->{id} } grep { !($_->{is_open}) } @{$groups->{$sec_keyword}};
    my @very_old_bugs   = map { $_->{id} } grep {
      $_->{created_at}->subtract_datetime_absolute($report_date)->seconds / 86_400 >= $self->very_old_days;
    } grep { ($_->{is_open}) } @{$groups->{$sec_keyword}};
    $result->{$sec_keyword} = {
      open            => [ sort @open ],
      closed          => [ sort @closed ],
      very_old_bugs   => [ sort @very_old_bugs ],
    };
  }

  return $result;
}

sub _is_bug_open {
  my ($self, $status, $is_stalled) = @_;
  return ($self->check_open_state->($status)) && !($is_stalled);
}

sub _find_team {
  my ($self, $product, $component) = @_;
  foreach my $team_key (keys %{$self->teams}) {
    my $team = $self->teams->{$team_key};
    if (exists $team->{$product}) {
      return $team_key if $team->{$product}->{all_components};
      return $team_key
        if any { lc $component eq lc $_ } @{$team->{$product}->{named_components}};
      return $team_key if any { $component =~ /^\Q$_\E/i }
      @{$team->{$product}->{prefixed_components}};
    }
  }
  return undef;
}


1;
