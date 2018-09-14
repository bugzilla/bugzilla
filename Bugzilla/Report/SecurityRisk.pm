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
use Bugzilla::Util qw(datetime_from);
use Bugzilla;
use DateTime;
use List::Util qw(any first sum);
use POSIX qw(ceil);
use Type::Utils;
use Types::Standard qw(Num Int Bool Str HashRef ArrayRef CodeRef Map Dict Enum);

my $DateTime = class_type { class => 'DateTime' };

has 'start_date' => (
    is       => 'ro',
    required => 1,
    isa      => $DateTime,
);

has 'end_date' => (
    is       => 'ro',
    required => 1,
    isa      => $DateTime,
);

has 'products' => (
    is       => 'ro',
    required => 1,
    isa      => ArrayRef [Str],
);

has 'sec_keywords' => (
    is       => 'ro',
    required => 1,
    isa      => ArrayRef [Str],
);

has 'initial_bug_ids' => (
    is  => 'lazy',
    isa => ArrayRef [Int],
);

has 'initial_bugs' => (
    is  => 'lazy',
    isa => HashRef [
        Dict [
            id         => Int,
            product    => Str,
            sec_level  => Str,
            is_open    => Bool,
            created_at => $DateTime,
        ],
    ],
);

has 'check_open_state' => (
    is => 'ro',
    isa => CodeRef,
    default => sub { return \&is_open_state; },
);

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
            date            => $DateTime,
            bugs_by_product => HashRef [
                Dict [
                    open   => ArrayRef [Int],
                    closed => ArrayRef [Int],
                    median_age_open => Num
                ]
            ],
            bugs_by_sec_keyword => HashRef [
                Dict [
                    open   => ArrayRef [Int],
                    closed => ArrayRef [Int],
                    median_age_open => Num
                ]
            ],
        ],
    ],
);

sub _build_initial_bug_ids {
    # TODO: Handle changes in product (e.g. gravyarding) by searching the events table
    # for changes to the 'product' field where one of $self->products is found in
    # the 'removed' field, add the related bug id to the list of initial bugs.
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    my $products     = join ', ', map { $dbh->quote($_) } @{ $self->products };
    my $sec_keywords = join ', ', map { $dbh->quote($_) } @{ $self->sec_keywords };
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
    my $bugs_list = Bugzilla::Bug->new_from_list( $self->initial_bug_ids );
    for my $bug (@$bugs_list) {
        $bugs->{ $bug->id } = {
            id        => $bug->id,
            product   => $bug->product,
            sec_level => (
                # Select the first keyword matching one of the target keywords
                # (of which there _should_ only be one found anyway).
                first {
                    my $x = $_;
                    grep { lc($_) eq lc( $x->name ) } @{ $self->sec_keywords }
                }
                @{ $bug->keyword_objects }
            )->name,
            is_open    => $self->check_open_state->( $bug->status->name ),
            created_at => datetime_from( $bug->creation_ts ),
        };
    }
    return $bugs;
}

sub _build_events {
    my ($self) = @_;
    return [] if !(@{$self->initial_bug_ids});
    my $bug_ids    = join ', ', @{ $self->initial_bug_ids };
    my $start_date = $self->start_date->ymd('-');
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
            AND bug_when >= '$start_date 00:00:00'
        GROUP BY bug_id , bug_when , field.name
    };
    my $result = Bugzilla->dbh->selectall_hashref( $query, 'bug_id' );
    my @events = values %$result;
    foreach my $event (@events) {
        $event->{bug_when} = datetime_from( $event->{bug_when} );
    }

    # We sort by reverse chronological order instead of ORDER BY
    # since values %hash doesn't guareentee any order.
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
    for ( my $report_date = $self->end_date; $report_date >= $self->start_date; $report_date->subtract( weeks => 1 ) ) {
        # We rewind events while there are still events existing which occured after the start
        # of the report week. The bugs will reflect a snapshot of how they were at the start of the week.
        # $self->events is ordered reverse chronologically, so the end of the array is the earliest event.
        while ( $e < @{ $self->events }
            && ( @{ $self->events }[$e] )->{bug_when} > $report_date )
        {
            my $event = @{ $self->events }[$e];
            my $bug   = $bugs->{ $event->{bug_id} };

            # Undo bug status changes
            if ( $event->{field_name} eq 'bug_status' ) {
                $bug->{is_open} = $self->check_open_state->( $event->{removed} );
            }

            # Undo keyword changes
            if ( $event->{field_name} eq 'keywords' ) {
                my $bug_sec_level = $bug->{sec_level};
                if ( $event->{added} =~ /\b\Q$bug_sec_level\E\b/ ) {
                    # If the currently set sec level was added in this event, remove it.
                    $bug->{sec_level} = undef;
                }
                if ( $event->{removed} ) {
                    # If a target sec keyword was removed, add the first one back.
                    my $removed_sec = first { $event->{removed} =~ /\b\Q$_\E\b/ } @{ $self->sec_keywords };
                    $bug->{sec_level} = $removed_sec if ($removed_sec);
                }
            }

            $e++;
        }

        # Remove uncreated bugs
        foreach my $bug_key ( keys %$bugs ) {
            if ( $bugs->{$bug_key}->{created_at} > $report_date ) {
                delete $bugs->{$bug_key};
            }
        }

        # Report!
        my $date_snapshot = $report_date->clone();
        my @bugs_snapshot = values %$bugs;
        my $result = {
            date                => $date_snapshot,
            bugs_by_product     => $self->_bugs_by_product( $date_snapshot, @bugs_snapshot ),
            bugs_by_sec_keyword => $self->_bugs_by_sec_keyword( $date_snapshot, @bugs_snapshot ),
        };
        push @results, $result;
    }

    return [reverse @results];
}

sub _bugs_by_product {
    my ( $self, $report_date, @bugs ) = @_;
    my $result = {};
    my $groups = {};
    foreach my $product ( @{ $self->products } ) {
        $groups->{$product} = [];
    }
    foreach my $bug (@bugs) {
        # We skip over bugs with no sec level which can happen during event rewinding.
        if ( $bug->{sec_level} ) {
            push @{ $groups->{ $bug->{product} } }, $bug;
        }
    }
    foreach my $product ( @{ $self->products } ) {
        my @open   = map { $_->{id} } grep { ( $_->{is_open} ) } @{ $groups->{$product} };
        my @closed = map { $_->{id} } grep { !( $_->{is_open} ) } @{ $groups->{$product} };
        my @ages = map { $_->{created_at}->subtract_datetime_absolute($report_date)->seconds / 86_400; }
            grep { ( $_->{is_open} ) } @{ $groups->{$product} };
        $result->{$product} = {
            open            => \@open,
            closed          => \@closed,
            median_age_open => @ages ? _median(@ages) : 0,
        };
    }

    return $result;
}

sub _bugs_by_sec_keyword {
    my ( $self, $report_date, @bugs ) = @_;
    my $result = {};
    my $groups = {};
    foreach my $sec_keyword ( @{ $self->sec_keywords } ) {
        $groups->{$sec_keyword} = [];
    }
    foreach my $bug (@bugs) {
        # We skip over bugs with no sec level which can happen during event rewinding.
        if ( $bug->{sec_level} ) {
            push @{ $groups->{ $bug->{sec_level} } }, $bug;
        }
    }
    foreach my $sec_keyword ( @{ $self->sec_keywords } ) {
        my @open   = map { $_->{id} } grep { ( $_->{is_open} ) } @{ $groups->{$sec_keyword} };
        my @closed = map { $_->{id} } grep { !( $_->{is_open} ) } @{ $groups->{$sec_keyword} };
        my @ages = map { $_->{created_at}->subtract_datetime_absolute($report_date)->seconds / 86_400 }
            grep { ( $_->{is_open} ) } @{ $groups->{$sec_keyword} };
        $result->{$sec_keyword} = {
            open            => \@open,
            closed          => \@closed,
            median_age_open => @ages ? _median(@ages) : 0,
        };
    }

    return $result;
}

sub _median {
    # From tlm @ https://www.perlmonks.org/?node_id=474564. Jul 14, 2005
    return sum( ( sort { $a <=> $b } @_ )[ int( $#_ / 2 ), ceil( $#_ / 2 ) ] ) / 2;
}

1;
