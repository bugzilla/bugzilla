# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Review::WebService;

use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Bug;
use Bugzilla::Component;
use Bugzilla::Error;

sub suggestions {
    my ($self, $params) = @_;
    my $dbh = Bugzilla->switch_to_shadow_db();

    my ($product, $component);
    if (exists $params->{bug_id}) {
        my $bug = Bugzilla::Bug->check($params->{bug_id});
        $product = $bug->product_obj;
        $component = $bug->component_obj;
    }
    elsif (exists $params->{product}) {
        $product = Bugzilla::Product->check($params->{product});
        if (exists $params->{component}) {
            $component = Bugzilla::Component->check({
                product => $product, name => $params->{component}
            });
        }
    }
    else {
        ThrowUserError("reviewer_suggestions_param_required");
    }

    my $reviewers = [];
    if ($component) {
        $reviewers = $component->reviewers_objs;
    }
    if (!@$reviewers) {
        $reviewers = $product->reviewers_objs;
    }

    my @result;
    foreach my $reviewer (@$reviewers) {
        push @result, {
            id    => $self->type('int', $reviewer->id),
            email => $self->type('email', $reviewer->login),
            name  => $self->type('string', $reviewer->name),
        };
    }
    return \@result;
}

sub rest_resources {
    return [
        # bug-id
        qr{^/review/suggestions/(\d+)$}, {
            GET => {
                method => 'suggestions',
                params => sub {
                    return { bug_id => $_[0] };
                },
            },
        },
        # product/component
        qr{^/review/suggestions/([^/]+)/(.+)$}, {
            GET => {
                method => 'suggestions',
                params => sub {
                    return { product => $_[0], component => $_[1] };
                },
            },
        },
        # just product
        qr{^/review/suggestions/([^/]+)$}, {
            GET => {
                method => 'suggestions',
                params => sub {
                    return { product => $_[0] };
                },
            },
        },
        # named parameters
        qr{^/review/suggestions$}, {
            GET => {
                method => 'suggestions',
            },
        },
    ];
};

1;

__END__
=head1 NAME

Bugzilla::Extension::Review::WebService - Functions for the Mozilla specific
'review' flag optimisations.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.

Although the data input and output is the same for JSONRPC, XMLRPC and REST,
the directions for how to access the data via REST is noted in each method
where applicable.

=head2 suggestions

B<EXPERIMENTAL>

=over

=item B<Description>

Returns the list of suggestions for reviewers.

=item B<REST>

GET /rest/review/suggestions/C<bug-id>

GET /rest/review/suggestions/C<product-name>

GET /rest/review/suggestions/C<product-name>/C<component-name>

GET /rest/review/suggestions?product=C<product-name>

GET /rest/review/suggestions?product=C<product-name>&component=C<component-name>

The returned data format is the same as below.

=item B<Params>

Query by Bug:

=over

=over

=item C<bug_id> (integer) - The bug ID.

=back

=back

Query by Product or Component:

=over

=over

=item C<product> (string) - The product name.

=item C<component> (string) - The component name (optional).  If providing a C<component>, a C<product> must also be provided.

=back

=back

=item B<Returns>

An array of hashes with the following keys/values:

=over

=item C<id> (integer) - The user's ID.

=item C<email> (string) - The user's email address (aka login).

=item C<name> (string) - The user's display name (may not match the Bugzilla "real name").

=back

=back
