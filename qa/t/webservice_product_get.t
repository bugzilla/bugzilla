# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

########################################
# Test for xmlrpc calls to:            #
# Product.get_selectable_products()    #
# Product.get_enterable_products()     #
# Product.get_accessible_products()    #
# Product.get()                        #
########################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Test::More tests => 134;
use QA::Util;
my ($config, @clients) = get_rpc_clients();

my $products = $clients[0]->bz_get_products();
my $public    = $products->{'Another Product'};
my $private   = $products->{'QA-Selenium-TEST'};
my $no_entry  = $products->{'QA Entry Only'};
my $no_search = $products->{'QA Search Only'};

my %id_map = reverse %$products;

my $tests = {
    'QA_Selenium_TEST' => {
        selectable => [$public, $private, $no_entry, $no_search],
        enterable  => [$public, $private, $no_entry, $no_search],
        accessible => [$public, $private, $no_entry, $no_search],
    },
    'unprivileged' => {
        selectable => [$public, $no_entry],
        not_selectable => $no_search,
        enterable  => [$public, $no_search],
        not_enterable => $no_entry,
        accessible => [$public, $no_entry, $no_search],
        not_accessible => $private,
    },
    '' => {
        selectable => [$public, $no_entry],
        not_selectable => $no_search,
        enterable  => [$public, $no_search],
        not_enterable => $no_entry,
        accessible => [$public, $no_entry, $no_search],
        not_accessible => $private,
    },
};

foreach my $rpc (@clients) {
    foreach my $user (keys %$tests) {
        my @selectable = @{ $tests->{$user}->{selectable} };
        my @enterable  = @{ $tests->{$user}->{enterable} };
        my @accessible = @{ $tests->{$user}->{accessible} };
        my $not_selectable = $tests->{$user}->{not_selectable};
        my $not_enterable  = $tests->{$user}->{not_enterable};
        my $not_accessible = $tests->{$user}->{not_accessible};

        $rpc->bz_log_in($user) if $user;
        $user ||= "Logged-out user";

        my $select_call =
            $rpc->bz_call_success('Product.get_selectable_products');
        my $select_ids = $select_call->result->{ids};
        foreach my $id (@selectable) {
            ok(grep($_ == $id, @$select_ids),
               "$user can select " . $id_map{$id});
        }
        if ($not_selectable) {
            ok(!grep($_ == $not_selectable, @$select_ids),
               "$user cannot select " . $id_map{$not_selectable});
        }

        my $enter_call =
            $rpc->bz_call_success('Product.get_enterable_products');
        my $enter_ids = $enter_call->result->{ids};
        foreach my $id (@enterable) {
            ok(grep($_ == $id, @$enter_ids), "$user can enter " . $id_map{$id});
        }
        if ($not_enterable) {
            ok(!grep($_ == $not_enterable, @$enter_ids),
               "$user cannot enter " . $id_map{$not_enterable});
        }

        my $access_call =
            $rpc->bz_call_success('Product.get_accessible_products');
        my $get_call = $rpc->bz_call_success('Product.get',
                                             { ids => \@accessible });
        my $products = $get_call->result->{products};
        my $expected_count = scalar @accessible;
        cmp_ok(scalar @$products, '==', $expected_count,
           "Product.get gets all $expected_count accessible products"
           . " for $user.");
        if ($not_accessible) {
            my $no_access_call = $rpc->bz_call_success(
                'Product.get', { ids => [$not_accessible] });
            ok(!scalar @{ $no_access_call->result->{products} },
               "$user gets 0 products when asking for "
               . $id_map{$not_accessible});
        }

        $rpc->bz_call_success('User.logout') if $user ne "Logged-out user";
    }
}
