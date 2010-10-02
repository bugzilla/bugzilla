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

# This is the same as a FieldTest, except that it uses normal URL
# parameters instead of Boolean Charts.
package Bugzilla::Test::Search::FieldTestNormal;
use strict;
use warnings;
use base qw(Bugzilla::Test::Search::FieldTest);

use Scalar::Util qw(blessed);

use constant CH_OPERATOR => {
    changedafter  => 'chfieldfrom',
    changedbefore => 'chfieldto',
    changedto     => 'chfieldvalue',
};

# Normally, we just clone a FieldTest because that's the best for performance,
# overall--that way we don't have to translate the value again. However,
# sometimes (like in Bugzilla::Test::Search's direct code) we just want
# to create a FieldTestNormal.
sub new {
    my $class = shift;
    my ($first_arg) = @_;
    if (blessed $first_arg
        and $first_arg->isa('Bugzilla::Test::Search::FieldTest'))
    {
        my $self = { %$first_arg };
        return bless $self, $class;
    }
    return $class->SUPER::new(@_);
}

sub name {
    my $self = shift;
    my $name = $self->SUPER::name(@_);
    return "$name (Normal Params)";
}

sub search_params {
    my ($self) = @_;
    my $field = $self->field;
    my $operator = $self->operator;
    my $value = $self->translated_value;
    if ($operator eq 'anyexact') {
        $value = [split(',', $value)];
    }
    
    if (my $ch_param = CH_OPERATOR->{$operator}) {
        if ($field eq 'creation_ts') {
            $field = '[Bug creation]';
        }
        return { chfield => $field, $ch_param => $value };
    }

    $field =~ s/\./_/g;
    return { $field => $value, "${field}_type" => $self->operator };
}

1;