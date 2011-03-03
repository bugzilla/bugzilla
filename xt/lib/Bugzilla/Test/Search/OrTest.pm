# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>

# This test combines two field/operator combinations using OR in
# a single boolean chart.
package Bugzilla::Test::Search::OrTest;
use base qw(Bugzilla::Test::Search::FieldTest);

use Bugzilla::Test::Search::Constants;
use List::MoreUtils qw(any uniq);

use constant type => 'OR';

###############
# Constructor #
###############

sub new {
    my $class = shift;
    my $self = { field_tests => [@_] };
    return bless $self, $class;
}

#############
# Accessors #
#############

sub field_tests { return @{ $_[0]->{field_tests} } }
sub search_test { ($_[0]->field_tests)[0]->search_test }

sub name {
    my ($self) = @_;
    my @names = map { $_->name } $self->field_tests;
    return join('-' . $self->type . '-', @names);
}

# In an OR test, bugs ARE supposed to be contained if they are contained
# by ANY test.
sub bug_is_contained {
    my ($self, $number) = @_;
    return any { $_->bug_is_contained($number) } $self->field_tests;
}

# Needed only for failure messages
sub debug_value {
    my ($self) = @_;
    my @values = map { $_->field . ' ' . $_->debug_value } $self->field_tests;
    return join(' ' . $self->type . ' ', @values);
}

########################
# SKIP & TODO Messages #
########################

sub _join_skip { () }
sub _join_broken_constant { OR_BROKEN }

sub field_not_yet_implemented {
    my ($self) = @_;
    foreach my $test ($self->field_tests) {
        if (grep { $_ eq $test->field } $self->_join_skip) {
            return $test->field . " is not yet supported in OR tests";
        }
    }
    return $self->_join_messages('field_not_yet_implemented');
}
sub invalid_field_operator_combination {
    my ($self) = @_;
    return $self->_join_messages('invalid_field_operator_combination');
}
sub search_known_broken {
    my ($self) = @_;
    return $self->_join_messages('search_known_broken');    
}

sub _join_messages {
    my ($self, $message_method) = @_;
    my @messages = map { $_->$message_method } $self->field_tests;
    @messages = grep { $_ } @messages;
    return join(' AND ', @messages);
}

sub _bug_will_actually_be_contained {
    my ($self, $number) = @_;
    my @results;
    foreach my $test ($self->field_tests) {
        if ($test->bug_is_contained($number)
            and !$test->contains_known_broken($number))
        {
            return 1;
        }
        elsif (!$test->bug_is_contained($number)
               and $test->contains_known_broken($number)) {
            return 1;
        }
    }
    return 0;
}

sub contains_known_broken {
    my ($self, $number) = @_;

    my $join_broken = $self->_join_known_broken;
    if (my $contains = $join_broken->{contains}) {
        my $contains_is_broken = grep { $_ == $number } @$contains;
        if ($contains_is_broken) {
            my $name = $self->name;
            return "$name contains $number is broken";
        }
        return undef;
    }

    return $self->_join_contains_known_broken($number);
}

sub _join_contains_known_broken {
    my ($self, $number) = @_;
    
    if ( ( $self->bug_is_contained($number)
           and !$self->_bug_will_actually_be_contained($number) )
        or ( !$self->bug_is_contained($number)
             and $self->_bug_will_actually_be_contained($number) ) )
    {
        my @messages = map { $_->contains_known_broken($number) } $self->field_tests;
        @messages = grep { $_ } @messages;
        return join(' AND ', @messages);
    }
    return undef;
}

sub _join_known_broken {
    my ($self) = @_;
    my $or_broken = $self->_join_broken_constant;
    foreach my $test ($self->field_tests) {
        @or_broken_for = map { $_->join_broken($or_broken) } $self->field_tests;
        @or_broken_for = grep { defined $_ } @or_broken_for;
        last if !@or_broken_for;
        $or_broken = $or_broken_for[0];
    }
    return $or_broken;
}

##############################
# Bugzilla::Search arguments #
##############################

sub search_columns {
    my ($self) = @_;
    my @columns = map { @{ $_->search_columns } } $self->field_tests;
    return [uniq @columns];
}

sub search_params {
    my ($self) = @_;
    my @all_params = map { $_->search_params } $self->field_tests;
    my %params;
    my $chart = 0;
    foreach my $item (@all_params) {
        $params{"field0-0-$chart"} = $item->{'field0-0-0'};
        $params{"type0-0-$chart"}  = $item->{'type0-0-0'};
        $params{"value0-0-$chart"} = $item->{'value0-0-0'};
        $chart++;
    }
    return \%params;
}

1;