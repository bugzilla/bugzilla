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
# The Initial Developer of the Original Code is NASA.
# Portions created by NASA are Copyright (C) 2006 San Jose State
# University Foundation. All Rights Reserved.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>

use strict;

package Bugzilla::Field::Choice;

use base qw(Bugzilla::Object);

use Bugzilla::Constants;
use Bugzilla::Error;

use Scalar::Util qw(blessed);

##################
# Initialization #
##################

use constant DB_COLUMNS => qw(
    id
    value
    sortkey
);

use constant NAME_FIELD => 'value';
use constant LIST_ORDER => 'sortkey, value';

##########################################
# Constructors and Database Manipulation #
##########################################

# When calling class methods, we aren't based on just one table,
# so we need some slightly hacky way to do DB_TABLE. We do it by overriding
# class methods and making them specify $_new_table. This is possible
# because we're always called from inside Bugzilla::Field, so it always
# has a $self to pass us which contains info about which field we're
# attached to.
#
# This isn't thread safe, but Bugzilla isn't a threaded application.
our $_new_table;
our $_current_field;
sub DB_TABLE {
    my $invocant = shift;
    if (blessed $invocant) {
        return $invocant->field->name;
    }
    return $_new_table;
}

sub new {
    my $class = shift;
    my ($params) = @_;
    _check_field_arg($params);
    my $self = $class->SUPER::new($params);
    _fix_return($self);
    return $self;
}

sub new_from_list {
    my $class = shift;
    my ($ids, $params) = @_;
    _check_field_arg($params);
    my $list = $class->SUPER::new_from_list(@_);
    _fix_return($list);
    return $list;
}

sub match {
    my $class = shift;
    my ($params) = @_;
    _check_field_arg($params);
    my $results = $class->SUPER::match(@_);
    _fix_return($results);
    return $results;
}

sub get_all {
    my $class = shift;
    _check_field_arg(@_);
    my @list = $class->SUPER::get_all(@_);
    _fix_return(\@list);
    return @list;
}

sub _check_field_arg {
    my ($params) = @_;
    my ($class, undef, undef, $func) = caller(1);
    if (!defined $params->{field}) {
        ThrowCodeError('param_required',
                       { function => "${class}::$func",
                         param    => 'field' });
    }
    elsif (!blessed $params->{field}) {
        ThrowCodeError('bad_arg', { function => "${class}::$func",
                                    argument => 'field' });
    }
    $_new_table = $params->{field}->name;
    $_current_field = $params->{field};
    delete $params->{field};
}

sub _fix_return {
    my $retval = shift;
    if (ref $retval eq 'ARRAY') {
        foreach my $obj (@$retval) {
            $obj->{field} = $_current_field;
        }
    }
    elsif (defined $retval) {
        $retval->{field} = $_current_field;
    }

    # We do this just to avoid any possible bugs where $_new_table or
    # $_current_field are set from a previous call. It also might save
    # a little memory under mod_perl by releasing $_current_field explicitly.
    undef $_new_table;
    undef $_current_field;
}

#############
# Accessors #
#############

sub sortkey { return $_[0]->{'sortkey'}; }
sub field   { return $_[0]->{'field'};   }

1;

__END__

=head1 NAME

Bugzilla::Field::Choice - A legal value for a <select>-type field.

=head1 SYNOPSIS

 my $field = new Bugzilla::Field({name => 'bug_status'});

 my $choice = new Bugzilla::Field::Choice({ field => $field, id => 1 });
 my $choice = new Bugzilla::Field::Choice({ field => $field, name => 'NEW' });

 my $choices = Bugzilla::Field::Choice->new_from_list([1,2,3], 
                                                      { field => $field});
 my $choices = Bugzilla::Field::Choice->get_all({ field => $field });
 my $choices = Bugzilla::Field::Choice->match({ sortkey => 10, 
                                                field => $field });

=head1 DESCRIPTION

This is an implementation of L<Bugzilla::Object>, but with a twist.
All the class methods require that you specify an additional C<field>
argument, which is a L<Bugzilla::Field> object that represents the
field whose value this is.

You can look at the L</SYNOPSIS> to see where this extra C<field>
argument goes in each function.

=head1 METHODS

=head2 Accessors

These are in addition to the standard L<Bugzilla::Object> accessors.

=over

=item C<sortkey>

The key that determines the sort order of this item.

=item C<field>

The L<Bugzilla::Field> object that this field value belongs to.

=back
