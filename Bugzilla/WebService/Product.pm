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
# Contributor(s): Marc Schumann <wurblzap@gmail.com>
#                 Mads Bondo Dydensborg <mbd@dbc.dk>

package Bugzilla::WebService::Product;

use strict;
use base qw(Bugzilla::WebService);
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::Error;
use Bugzilla::Constants;
use Bugzilla::WebService::Constants;
use Bugzilla::WebService::Util qw(validate);

use constant READ_ONLY => qw(
    get
    get_accessible_products
    get_enterable_products
    get_selectable_products
);

##################################################
# Add aliases here for method name compatibility #
##################################################

BEGIN { *get_products = \&get }

# Get the ids of the products the user can search
sub get_selectable_products {
    return {ids => [map {$_->id} @{Bugzilla->user->get_selectable_products}]}; 
}

# Get the ids of the products the user can enter bugs against
sub get_enterable_products {
    return {ids => [map {$_->id} @{Bugzilla->user->get_enterable_products}]}; 
}

# Get the union of the products the user can search and enter bugs against.
sub get_accessible_products {
    return {ids => [map {$_->id} @{Bugzilla->user->get_accessible_products}]}; 
}

# Get a list of actual products, based on list of ids
sub get {
    my ($self, $params) = validate(@_, 'ids');
    
    # Only products that are in the users accessible products, 
    # can be allowed to be returned
    my $accessible_products = Bugzilla->user->get_accessible_products;

    # Create a hash with the ids the user wants
    my %ids = map { $_ => 1 } @{$params->{ids}};
    
    # Return the intersection of this, by grepping the ids from 
    # accessible products.
    my @requested_accessible = grep { $ids{$_->id} } @$accessible_products;

    # Now create a result entry for each.
    my @products = 
        map {{
               internals   => $_,
               id          => $self->type('int', $_->id),
               name        => $self->type('string', $_->name),
               description => $self->type('string', $_->description),
             }
        } @requested_accessible;

    return { products => \@products };
}

sub create {
    my ($self, $params) = @_;

    Bugzilla->login(LOGIN_REQUIRED);
    Bugzilla->user->in_group('editcomponents') 
        || ThrowUserError("auth_failure", { group  => "editcomponents",
                                            action => "add",
                                            object => "products"});
    # Create product
    my $product = Bugzilla::Product->create({
        allows_unconfirmed => $params->{has_unconfirmed},
        classification     => $params->{classification},
        name               => $params->{name},
        description        => $params->{description},
        version            => $params->{version},
        defaultmilestone   => $params->{default_milestone},
        isactive           => $params->{is_open},
        create_series      => $params->{create_series}
    });
    return { id => $self->type('int', $product->id) };
}

1;

__END__

=head1 NAME

Bugzilla::Webservice::Product - The Product API

=head1 DESCRIPTION

This part of the Bugzilla API allows you to list the available Products and
get information about them.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.

=head1 List Products

=head2 get_selectable_products

B<EXPERIMENTAL>

=over

=item B<Description>

Returns a list of the ids of the products the user can search on.

=item B<Params> (none)

=item B<Returns>    

A hash containing one item, C<ids>, that contains an array of product
ids.

=item B<Errors> (none)

=back

=head2 get_enterable_products

B<EXPERIMENTAL>

=over

=item B<Description>

Returns a list of the ids of the products the user can enter bugs
against.

=item B<Params> (none)

=item B<Returns>

A hash containing one item, C<ids>, that contains an array of product
ids.

=item B<Errors> (none)

=back

=head2 get_accessible_products

B<UNSTABLE>

=over

=item B<Description>

Returns a list of the ids of the products the user can search or enter
bugs against.

=item B<Params> (none)

=item B<Returns>

A hash containing one item, C<ids>, that contains an array of product
ids.

=item B<Errors> (none)

=back

=head2 get

B<EXPERIMENTAL>

=over

=item B<Description>

Returns a list of information about the products passed to it.

Note: Can also be called as "get_products" for compatibilty with Bugzilla 3.0 API.

=item B<Params>

A hash containing one item, C<ids>, that is an array of product ids. 

=item B<Returns> 

A hash containing one item, C<products>, that is an array of
hashes. Each hash describes a product, and has the following items:
C<id>, C<name>, C<description>, and C<internals>. The C<id> item is
the id of the product. The C<name> item is the name of the
product. The C<description> is the description of the
product. Finally, the C<internals> is an internal representation of
the product.

Note, that if the user tries to access a product that is not in the
list of accessible products for the user, or a product that does not
exist, that is silently ignored, and no information about that product
is returned.

=item B<Errors> (none)

=back

=head1 Product Creation

=head2 create

B<EXPERIMENTAL>

=over

=item B<Description>

This allows you to create a new product in Bugzilla.

=item B<Params> 

Some params must be set, or an error will be thrown. These params are marked Required.

=over

=item C<name>

B<Required> C<string> The name of this product. Must be unique.

=item C<description>

B<Required> C<string> A description for this product. Allows some simple HTML.

=item C<version> 

B<Required> C<string> The default version for this product.

=item C<has_unconfirmed> 

C<boolean> Allows unconfirmed bugs in the product.

=item C<classification>

C<boolean> Classification wich contains the product.

=item C<default_milestone> 

C<boolean> The default milestone of this product.

=item C<is_open> 

C<boolean> True if the product is currently allowing bugs to be entered into it.

=item C<create_series> 

C<boolean> Set if series are creating for the new product. 

=back

=item B<Returns>    

A hash with one element, id. This is the id of the newly-filed product.

=item B<Errors>

=over

=item 700 (Product blank name)

You must specify a non blank name for this product.

=item 701 (Product name too long)

The name specified for this product was longer than the maximum allowed length.

=item 702 (Product name already exists)

You specified the name of a product that already exists. (Product names must be globally unique in Bugzilla.)

=item 703 (Product must have description)

You must specify a description for this product.

=item 704 (Product must have version)

You must specify a version for this product.

=item 705 (Product must define a defaut milestone)

You must define a default milestone.

=back

=back

=cut
