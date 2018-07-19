# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ComponentWatching::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Product;
use Bugzilla::User;

sub rest_resources {
    return [
        qr{^/component-watching$}, {
            GET => {
                method => 'list',
            },
            POST => {
                method => 'add',
            },
        },
        qr{^/component-watching/(\d+)$}, {
            GET => {
                method => 'get',
                params => sub {
                    return { id => $_[0] }
                },
            },
            DELETE => {
                method => 'remove',
                params => sub {
                    return { id => $_[0] }
                },
            },
        },
    ];
}

#
# API methods based on Bugzilla::Extension::ComponentWatching->user_preferences
#

sub list {
    my ($self, $params) = @_;
    my $user = Bugzilla->login(LOGIN_REQUIRED);

    return Bugzilla::Extension::ComponentWatching::_getWatches($user);
}

sub add {
    my ($self, $params) = @_;
    my $user = Bugzilla->login(LOGIN_REQUIRED);
    my $result;

    # load product and verify access
    my $productName = $params->{'product'};
    my $product = Bugzilla::Product->new({ name => $productName, cache => 1 });
    unless ($product && $user->can_access_product($product)) {
        ThrowUserError('product_access_denied', { product => $productName });
    }

    my $ra_componentNames = $params->{'component'};
    $ra_componentNames = [$ra_componentNames || ''] unless ref($ra_componentNames);

    if (grep { $_ eq '' } @$ra_componentNames) {
        # watching a product
        $result = Bugzilla::Extension::ComponentWatching::_addProductWatch($user, $product);

    } else {
        # watching specific components
        foreach my $componentName (@$ra_componentNames) {
            my $component = Bugzilla::Component->new({
                name => $componentName, product => $product, cache => 1
            });
            unless ($component) {
                ThrowUserError('product_access_denied', { product => $productName });
            }
            $result = Bugzilla::Extension::ComponentWatching::_addComponentWatch($user, $component);
        }
    }

    Bugzilla::Extension::ComponentWatching::_addDefaultSettings($user);

    return $result;
}

sub get {
    my ($self, $params) = @_;
    my $user = Bugzilla->login(LOGIN_REQUIRED);

    return Bugzilla::Extension::ComponentWatching::_getWatches($user, $params->{'id'});
}

sub remove {
    my ($self, $params) = @_;
    my $user = Bugzilla->login(LOGIN_REQUIRED);
    my %result = (status => Bugzilla::Extension::ComponentWatching::_deleteWatch($user, $params->{'id'}));

    return \%result;
}

1;
