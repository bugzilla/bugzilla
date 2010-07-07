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

# Calling CGI::param over and over turned out to be one of the slowest
# parts of search.t. So we create a simpler thing here that just supports
# "param" in a fast way.
package Bugzilla::Test::Search::FakeCGI;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub param {
    my ($self, $name, @values) = @_;
    if (!defined $name) {
        return keys %$self;
    }

    if (@values) {
        if (ref $values[0] eq 'ARRAY') {
            $self->{$name} = $values[0];
        }
        else {
            $self->{$name} = \@values;
        }
    }
    
    return () if !exists $self->{$name};
    
    my $item = $self->{$name};
    return wantarray ? @{ $item || [] } : $item->[0];
}

sub delete {
    my ($self, $name) = @_;
    delete $self->{$name};
}

# We don't need to do this, because we don't use old params in search.t.
sub convert_old_params {}

1;