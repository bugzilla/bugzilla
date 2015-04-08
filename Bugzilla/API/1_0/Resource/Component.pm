# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::1_0::Resource::Component;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::API::1_0::Constants;
use Bugzilla::API::1_0::Util;

use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;

use Moo;

extends 'Bugzilla::API::1_0::Resource';

##############
# Constants  #
##############

use constant PUBLIC_METHODS => qw(
    create
);

use constant CREATE_MAPPED_FIELDS => {
    default_assignee   => 'initialowner',
    default_qa_contact => 'initialqacontact',
    default_cc         => 'initial_cc',
    is_open            => 'isactive',
};

use constant MAPPED_FIELDS => {
    is_open => 'is_active',
};

use constant MAPPED_RETURNS => {
    initialowner     => 'default_assignee',
    initialqacontact => 'default_qa_contact',
    cc_list          => 'default_cc',
    isactive         => 'isopen',
};

sub REST_RESOURCES {
    my $rest_resources = [
        qr{^/component$}, {
            POST => {
                method => 'create',
                success_code => STATUS_CREATED
            }
        },
        qr{^/component/(\d+)$}, {
            PUT => {
                method => 'update',
                params => sub {
                    return { ids => [ $_[0] ] };
                }
            },
            DELETE => {
                method => 'delete',
                params => sub {
                    return { ids => [ $_[0] ] };
                }
            },
        },
        qr{^/component/([^/]+)/([^/]+)$}, {
            PUT => {
                method => 'update',
                params => sub {
                    return { names => [ { product => $_[0], component => $_[1] } ] };
                }
            },
            DELETE => {
                method => 'delete',
                params => sub {
                    return { names => [ { product => $_[0], component => $_[1] } ] };
                }
            },
        },
    ];
    return $rest_resources;
}

############
# Methods  #
############

sub create {
    my ($self, $params) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    $user->in_group('editcomponents')
        || scalar @{ $user->get_products_by_permission('editcomponents') }
        || ThrowUserError('auth_failure', { group  => 'editcomponents',
                                            action => 'edit',
                                            object => 'components' });

    my $product = $user->check_can_admin_product($params->{product});

    # Translate the fields
    my $values = translate($params, CREATE_MAPPED_FIELDS);
    $values->{product} = $product;

    # Create the component and return the newly created id.
    my $component = Bugzilla::Component->create($values);
    return { id => as_int($component->id) };
}

sub _component_params_to_objects {
    # We can't use Util's _param_to_objects since name is a hash
    my $params = shift;
    my $user   = Bugzilla->user;

    my @components = ();

    if (defined $params->{ids}) {
        push @components, @{ Bugzilla::Component->new_from_list($params->{ids}) };
    }

    if (defined $params->{names}) {
        # To get the component objects for product/component combination
        # first obtain the product object from the passed product name
        foreach my $name_hash (@{$params->{names}}) {
            my $product = $user->can_admin_product($name_hash->{product});
            push @components, @{ Bugzilla::Component->match({
                product_id => $product->id,
                name       => $name_hash->{component}
            })};
        }
    }

    my %seen_component_ids = ();

    my @accessible_components;
    foreach my $component (@components) {
        # Skip if we already included this component
        next if $seen_component_ids{$component->id}++;

        # Can the user see and admin this product?
        my $product = $component->product;
        $user->check_can_admin_product($product->name);

        push @accessible_components, $component;
    }

    return \@accessible_components;
}

sub update {
    my ($self, $params) = @_;
    my $dbh  = Bugzilla->dbh;
    my $user = Bugzilla->user;

    Bugzilla->login(LOGIN_REQUIRED);
    $user->in_group('editcomponents')
        || scalar @{ $user->get_products_by_permission('editcomponents') }
        || ThrowUserError("auth_failure", { group  => "editcomponents",
                                            action => "edit",
                                            object => "components" });

    defined($params->{names}) || defined($params->{ids})
        || ThrowCodeError('params_required',
               { function => 'Component.update', params => ['ids', 'names'] });

    my $component_objects = _component_params_to_objects($params);

    # If the user tries to change component name for several
    # components of the same product then throw an error
    if ($params->{name}) {
        my %unique_product_comps;
        foreach my $comp (@$component_objects) {
            if($unique_product_comps{$comp->product_id}) {
                ThrowUserError("multiple_components_update_not_allowed");
            }
            else {
                $unique_product_comps{$comp->product_id} = 1;
            }
        }
    }

    my $values = translate($params, MAPPED_FIELDS);

    # We delete names and ids to keep only new values to set.
    delete $values->{names};
    delete $values->{ids};

    $dbh->bz_start_transaction();
    foreach my $component (@$component_objects) {
        $component->set_all($values);
    }

    my %changes;
    foreach my $component (@$component_objects) {
        my $returned_changes = $component->update();
        $changes{$component->id} = translate($returned_changes, MAPPED_RETURNS);
    }
    $dbh->bz_commit_transaction();

    my @result;
    foreach my $component (@$component_objects) {
        my %hash = (
            id      => $component->id,
            changes => {},
        );

        foreach my $field (keys %{ $changes{$component->id} }) {
            my $change = $changes{$component->id}->{$field};

            if ($field eq 'default_assignee'
                || $field eq 'default_qa_contact'
                || $field eq 'default_cc'
            ) {
                # We need to convert user ids to login names
                my @old_user_ids = split(/[,\s]+/, $change->[0]);
                my @new_user_ids = split(/[,\s]+/, $change->[1]);

                my @old_users = map { $_->login }
                    @{Bugzilla::User->new_from_list(\@old_user_ids)};
                my @new_users = map { $_->login }
                    @{Bugzilla::User->new_from_list(\@new_user_ids)};

                $hash{changes}{$field} = {
                    removed => as_string(join(', ', @old_users)),
                    added   => as_string(join(', ', @new_users)),
                };
            }
            else {
                $hash{changes}{$field} = {
                    removed => as_string($change->[0]),
                    added   => as_string($change->[1])
                };
            }
        }

        push(@result, \%hash);
    }

    return { components => \@result };
}

sub delete {
    my ($self, $params) = @_;

    my $dbh  = Bugzilla->dbh;
    my $user = Bugzilla->user;

    Bugzilla->login(LOGIN_REQUIRED);
    $user->in_group('editcomponents')
        || scalar @{ $user->get_products_by_permission('editcomponents') }
        || ThrowUserError("auth_failure", { group  => "editcomponents",
                                            action => "edit",
                                            object => "components" });

    defined($params->{names}) || defined($params->{ids})
        || ThrowCodeError('params_required',
               { function => 'Component.delete', params => ['ids', 'names'] });

    my $component_objects = _component_params_to_objects($params);

    $dbh->bz_start_transaction();
    my %changes;
    foreach my $component (@$component_objects) {
        my $returned_changes = $component->remove_from_db();
    }
    $dbh->bz_commit_transaction();

    my @result;
    foreach my $component (@$component_objects) {
        push @result, { id => $component->id };
    }

    return { components => \@result };
}

1;

__END__

=head1 NAME

Bugzilla::API::1_0::Resource::Component - The Component API

=head1 DESCRIPTION

This part of the Bugzilla API allows you to deal with the available product components.
You will be able to get information about them as well as manipulate them.

=head1 METHODS

=head2 create

=over

=item B<Description>

This allows you to create a new component in Bugzilla.

=item B<Params>

Some params must be set, or an error will be thrown. These params are
marked B<Required>.

=over

=item C<name>

B<Required> C<string> The name of the new component.

=item C<product>

B<Required> C<string> The name of the product that the component must be
added to. This product must already exist, and the user have the necessary
permissions to edit components for it.

=item C<description>

B<Required> C<string> The description of the new component.

=item C<default_assignee>

B<Required> C<string> The login name of the default assignee of the component.

=item C<default_cc>

C<array> An array of strings with each element representing one login name of the default CC list.

=item C<default_qa_contact>

C<string> The login name of the default QA contact for the component.

=item C<is_open>

C<boolean> 1 if you want to enable the component for bug creations. 0 otherwise. Default is 1.

=back

=item B<Returns>

A hash with one key: C<id>. This will represent the ID of the newly-added
component.

=item B<Errors>

=over

=item 304 (Authorization Failure)

You are not authorized to create a new component.

=item 1200 (Component already exists)

The name that you specified for the new component already exists in the
specified product.

=back

=item B<History>

=over

=item Added in Bugzilla B<5.0>.

=back

=back

=head2 update

=over

=item B<Description>

This allows you to update one or more components in Bugzilla.

=item B<REST>

PUT /rest/component/<component_id>

PUT /rest/component/<product_name>/<component_name>

The params to include in the PUT body as well as the returned data format,
are the same as below. The C<ids> and C<names> params will be overridden as
it is pulled from the URL path.

=item B<Params>

B<Note:> The following parameters specify which components you are updating.
You must set one or both of these parameters.

=over

=item C<ids>

C<array> of C<int>s. Numeric ids of the components that you wish to update.

=item C<names>

C<array> of C<hash>es. Names of the components that you wish to update. The
hash keys are C<product> and C<component>, representing the name of the product
and the component you wish to change.

=back

B<Note:> The following parameters specify the new values you want to set for
the components you are updating.

=over

=item C<name>

C<string> A new name for this component. If you try to set this while updating
more than one component for a product, an error will occur, as component names
must be unique per product.

=item C<description>

C<string> Update the long description for these components to this value.

=item C<default_assignee>

C<string> The login name of the default assignee of the component.

=item C<default_cc>

C<array> An array of strings with each element representing one login name of the default CC list.

=item C<default_qa_contact>

C<string> The login name of the default QA contact for the component.

=item C<is_open>

C<boolean> True if the component is currently allowing bugs to be entered
into it, False otherwise.

=back

=item B<Returns>

A C<hash> with a single field "components". This points to an array of hashes
with the following fields:

=over

=item C<id>

C<int> The id of the component that was updated.

=item C<changes>

C<hash> The changes that were actually done on this component. The keys are
the names of the fields that were changed, and the values are a hash
with two keys:

=over

=item C<added>

C<string> The value that this field was changed to.

=item C<removed>

C<string> The value that was previously set in this field.

=back

Note that booleans will be represented with the strings '1' and '0'.

Here's an example of what a return value might look like:

 {
   components => [
     {
       id => 123,
       changes => {
         name => {
           removed => 'FooName',
           added   => 'BarName'
         },
         default_assignee => {
           removed => 'foo@company.com',
           added   => 'bar@company.com',
         }
       }
     }
   ]
 }

=back

=item B<Errors>

=over

=item 51 (User does not exist)

One of the contact e-mail addresses is not a valid Bugzilla user.

=item 106 (Product access denied)

The product you are trying to modify does not exist or you don't have access to it.

=item 706 (Product admin denied)

You do not have the permission to change components for this product.

=item 105 (Component name too long)

The name specified for this component was longer than the maximum
allowed length.

=item 1200 (Component name already exists)

You specified the name of a component that already exists.
(Component names must be unique per product in Bugzilla.)

=item 1210 (Component blank name)

You must specify a non-blank name for this component.

=item 1211 (Component must have description)

You must specify a description for this component.

=item 1212 (Component name is not unique)

You have attempted to set more than one component in the same product with the
same name. Component names must be unique in each product.

=item 1213 (Component needs a default assignee)

A default assignee is required for this component.

=back

=item B<History>

=over

=item Added in Bugzilla B<5.0>.

=back

=back

=head2 delete

=over

=item B<Description>

This allows you to delete one or more components in Bugzilla.

=item B<REST>

DELETE /rest/component/<component_id>

DELETE /rest/component/<product_name>/<component_name>

The params to include in the PUT body as well as the returned data format,
are the same as below. The C<ids> and C<names> params will be overridden as
it is pulled from the URL path.

=item B<Params>

B<Note:> The following parameters specify which components you are deleting.
You must set one or both of these parameters.

=over

=item C<ids>

C<array> of C<int>s. Numeric ids of the components that you wish to delete.

=item C<names>

C<array> of C<hash>es. Names of the components that you wish to delete. The
hash keys are C<product> and C<component>, representing the name of the product
and the component you wish to delete.

=back

=item B<Returns>

A C<hash> with a single field "components". This points to an array of hashes
with the following field:

=over

=item C<id>

C<int> The id of the component that was deleted.

=back

=item B<Errors>

=over

=item 106 (Product access denied)

The product you are trying to modify does not exist or you don't have access to it.

=item 706 (Product admin denied)

You do not have the permission to delete components for this product.

=item 1202 (Component has bugs)

The component you are trying to delete currently has bugs assigned to it.
You must move these bugs before trying to delete the component.

=back

=item B<History>

=over

=item Added in Bugzilla B<5.0>

=back

=back

=head1 B<Methods in need of POD>

=over

=item REST_RESOURCES

=back
