# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Ember::FakeBug;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Bug;

our $AUTOLOAD;

sub new {
    my $class = shift;
    my $self = shift;
    bless $self, $class;
    return $self;
}

sub AUTOLOAD {
    my $self = shift;
    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    return exists $self->{$name} ? $self->{$name} : undef;
}

sub check_can_change_field {
    return Bugzilla::Bug::check_can_change_field(@_);
}

sub id { return undef; }
sub product_obj { return $_[0]->{product_obj}; }

sub choices {
    my $self = shift;
    return $self->{'choices'} if exists $self->{'choices'};
    return {} if $self->{'error'};
    my $user = Bugzilla->user;

    my @products = @{ $user->get_enterable_products };
    # The current product is part of the popup, even if new bugs are no longer
    # allowed for that product
    if (!grep($_->name eq $self->product_obj->name, @products)) {
        unshift(@products, $self->product_obj);
    }

    my @statuses = @{ Bugzilla::Status->can_change_to };

    # UNCONFIRMED is only a valid status if it is enabled in this product.
    if (!$self->product_obj->allows_unconfirmed) {
        @statuses = grep { $_->name ne 'UNCONFIRMED' } @statuses;
    }

    my %choices = (
        bug_status       => \@statuses,
        product          => \@products,
        component        => $self->product_obj->components,
        version          => $self->product_obj->versions,
        target_milestone => $self->product_obj->milestones,
    );

    my $resolution_field = new Bugzilla::Field({ name => 'resolution' });
    # Don't include the empty resolution in drop-downs.
    my @resolutions = grep($_->name, @{ $resolution_field->legal_values });
    $choices{'resolution'} = \@resolutions;

    $self->{'choices'} = \%choices;
    return $self->{'choices'};
}

1;

