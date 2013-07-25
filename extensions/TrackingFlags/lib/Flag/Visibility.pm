# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TrackingFlags::Flag::Visibility;

use base qw(Bugzilla::Object);

use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::Product;
use Bugzilla::Component;
use Scalar::Util qw(blessed);

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'tracking_flags_visibility';

use constant DB_COLUMNS => qw(
    id
    tracking_flag_id
    product_id
    component_id
);

use constant LIST_ORDER => 'id';

use constant UPDATE_COLUMNS => (); # imutable

use constant VALIDATORS => {
    tracking_flag_id => \&_check_tracking_flag,
    product_id       => \&_check_product,
    component_id     => \&_check_component,
};

###############################
####      Methods          ####
###############################

sub match {
    my $class= shift;
    my ($params) = @_;
    my $dbh = Bugzilla->dbh;

    # Allow matching component and product by name
    # (in addition to matching by ID).
    # Borrowed from Bugzilla::Bug::match
    my %translate_fields = (
        product     => 'Bugzilla::Product',
        component   => 'Bugzilla::Component',
    );

    foreach my $field (keys %translate_fields) {
        my @ids;
        # Convert names to ids. We use "exists" everywhere since people can
        # legally specify "undef" to mean IS NULL
        if (exists $params->{$field}) {
            my $names = $params->{$field};
            my $type = $translate_fields{$field};
            my $objects = Bugzilla::Object::match($type, { name => $names });
            push(@ids, map { $_->id } @$objects);
        }
        # You can also specify ids directly as arguments to this function,
        # so include them in the list if they have been specified.
        if (exists $params->{"${field}_id"}) {
            my $current_ids = $params->{"${field}_id"};
            my @id_array = ref $current_ids ? @$current_ids : ($current_ids);
            push(@ids, @id_array);
        }
        # We do this "or" instead of a "scalar(@ids)" to handle the case
        # when people passed only invalid object names. Otherwise we'd
        # end up with a SUPER::match call with zero criteria (which dies).
        if (exists $params->{$field} or exists $params->{"${field}_id"}) {
            delete $params->{$field};
            $params->{"${field}_id"} = scalar(@ids) == 1 ? [ $ids[0] ] : \@ids;
        }
    }

    # If we aren't matching on the product, use the default matching code
    if (!exists $params->{product_id}) {
        return $class->SUPER::match(@_);
    }

    my @criteria = ("1=1");

    if ($params->{product_id}) {
        push(@criteria, $dbh->sql_in('product_id', $params->{'product_id'}));
        if ($params->{component_id}) {
            my $component_id = $params->{component_id};
            push(@criteria, "(" . $dbh->sql_in('component_id', $params->{'component_id'}) .
                            " OR component_id IS NULL)");
        }
    }

    my $where = join(' AND ', @criteria);
    my $flag_ids = $dbh->selectcol_arrayref("SELECT id
                                               FROM tracking_flags_visibility
                                              WHERE $where");

    return Bugzilla::Extension::TrackingFlags::Flag::Visibility->new_from_list($flag_ids);
}

###############################
####      Validators       ####
###############################

sub _check_tracking_flag {
    my ($invocant, $flag) = @_;
    if (blessed $flag) {
        return $flag->flag_id;
    }
    $flag = Bugzilla::Extension::TrackingFlags::Flag->new($flag)
        || ThrowCodeError('tracking_flags_invalid_param', { name => 'flag_id', value => $flag });
    return $flag->flag_id;
}

sub _check_product {
    my ($invocant, $product) = @_;
    if (blessed $product) {
        return $product->id;
    }
    $product = Bugzilla::Product->new($product)
        || ThrowCodeError('tracking_flags_invalid_param', { name => 'product_id', value => $product });
    return $product->id;
}

sub _check_component {
    my ($invocant, $component) = @_;
    return undef unless defined $component;
    if (blessed $component) {
        return $component->id;
    }
    $component = Bugzilla::Component->new($component)
        || ThrowCodeError('tracking_flags_invalid_param', { name => 'component_id', value => $component });
    return $component->id;
}

###############################
####      Accessors        ####
###############################

sub tracking_flag_id { return $_[0]->{'tracking_flag_id'}; }
sub product_id       { return $_[0]->{'product_id'};       }
sub component_id     { return $_[0]->{'component_id'};     }

sub tracking_flag {
    my ($self) = @_;
    $self->{'tracking_flag'} ||= Bugzilla::Extension::TrackingFlags::Flag->new($self->tracking_flag_id);
    return $self->{'tracking_flag'};
}

sub product {
    my ($self) = @_;
    $self->{'product'} ||= Bugzilla::Product->new($self->product_id);
    return $self->{'product'};
}

sub component {
    my ($self) = @_;
    return undef unless $self->component_id;
    $self->{'component'} ||= Bugzilla::Component->new($self->component_id);
    return $self->{'component'};
}

1;
