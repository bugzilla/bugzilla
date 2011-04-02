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
# The Initial Developer of the Original Code is BugzillaSource, Inc.
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Search::Clause;
use strict;
use Bugzilla::Search::Condition qw(condition);

sub new {
    my ($class, $joiner) = @_;
    bless { joiner => $joiner || 'AND' }, $class;
}

sub children {
    my ($self) = @_;
    $self->{children} ||= [];
    return $self->{children};
}

sub joiner { return $_[0]->{joiner} }

sub has_children {
    my ($self) = @_;
    return scalar(@{ $self->children }) > 0 ? 1 : 0;
}

sub has_conditions {
    my ($self) = @_;
    my $children = $self->children;
    return 1 if grep { $_->isa('Bugzilla::Search::Condition') } @$children;
    foreach my $child (@$children) {
        return 1 if $child->has_conditions;
    }
    return 0;
}

sub add {
    my $self = shift;
    my $children = $self->children;
    if (@_ == 3) {
        push(@$children, condition(@_));
        return;
    }
    
    my ($child) = @_;
    return if !defined $child;
    $child->isa(__PACKAGE__) || $child->isa('Bugzilla::Search::Condition')
        || die 'child not the right type: ' . $child;
    push(@{ $self->children }, $child);
}

sub negate {
    my ($self, $value) = @_;
    if (@_ == 2) {
        $self->{negate} = $value;
    }
    return $self->{negate};
}

sub walk_conditions {
    my ($self, $callback) = @_;
    foreach my $child (@{ $self->children }) {
        if ($child->isa('Bugzilla::Search::Condition')) {
            $callback->($child);
        }
        else {
            $child->walk_conditions($callback);
        }
    }
}

sub as_string {
    my ($self) = @_;
    my @strings;
    foreach my $child (@{ $self->children }) {
        next if $child->isa(__PACKAGE__) && !$child->has_conditions;
        next if $child->isa('Bugzilla::Search::Condition')
                && !$child->translated;

        my $string = $child->as_string;
        if ($self->joiner eq 'AND') {
            $string = "( $string )" if $string =~ /OR/;
        }
        else {
            $string = "( $string )" if $string =~ /AND/;
        }
        push(@strings, $string);
    }
    
    my $sql = join(' ' . $self->joiner . ' ', @strings);
    $sql = "NOT( $sql )" if $sql && $self->negate;
    return $sql;
}


1;