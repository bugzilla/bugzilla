# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

############################################
# Test for xmlrpc call to Product.create() #
############################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Test::More tests => 121;
use QA::Util;

use constant DESCRIPTION => 'Product created by Product.create';
use constant PROD_VERSION => 'unspecified';

sub post_success {
    my ($call, $test, $self) = @_;
    my $args = $test->{args};
    my $prod_id = $call->result->{id};
    ok($prod_id, "Got a non-zero product ID: $prod_id");

    $call = $self->bz_call_success("Product.get", {ids => [$prod_id]});
    my $product = $call->result->{products}->[0];
    my $prod_name = $product->{name};
    my $is_active = defined $args->{is_open} ? $args->{is_open} : 1;
    ok($product->{is_active} == $is_active,
       "Product $prod_name has the correct value for is_active/is_open: $is_active");
    my $has_unco = defined $args->{has_unconfirmed} ? $args->{has_unconfirmed} : 1;
    ok($product->{has_unconfirmed} == $has_unco,
       "Product $prod_name has the correct value for has_unconfirmed: $has_unco");
}

my ($config, $xmlrpc, $jsonrpc, $jsonrpc_get) = get_rpc_clients();

my @tests = (
    { args  => { name => random_string(20), version => PROD_VERSION,
                 description => DESCRIPTION },
      error => 'You must log in',
      test  => 'Logged-out user cannot call Product.create',
    },
    { user  => 'unprivileged',
      args  => { name => random_string(20), version => PROD_VERSION,
                 description => DESCRIPTION },
      error => 'you are not authorized',
      test  => 'Unprivileged user cannot call Product.create',
    },
    { user  => 'admin',
      args  => { version => PROD_VERSION, description => DESCRIPTION },
      error => 'You must enter a name',
      test  => 'Missing name to Product.create',
    },
    { user  => 'admin',
      args  => { name => random_string(20), version => PROD_VERSION },
      error => 'You must enter a description',
      test  => 'Missing description to Product.create',
    },
    { user  => 'admin',
      args  => { name => random_string(20), description => DESCRIPTION },
      error => 'You must enter a valid version',
      test  => 'Missing version to Product.create',
    },
    { user  => 'admin',
      args  => { name => '', version => PROD_VERSION, description => DESCRIPTION },
      error => 'You must enter a name',
      test  => 'Name to Product.create cannot be empty',
    },
    { user  => 'admin',
      args  => { name => random_string(20), version => PROD_VERSION, description => '' },
      error => 'You must enter a description',
      test  => 'Description to Product.create cannot be empty',
    },
    { user  => 'admin',
      args  => { name => random_string(20), version => '', description => DESCRIPTION },
      error => 'You must enter a valid version',
      test  => 'Version to Product.create cannot be empty',
    },
    { user  => 'admin',
      args  => { name => random_string(20000), version => PROD_VERSION,
                 description => DESCRIPTION },
      error => 'The name of a product is limited',
      test  => 'Name to Product.create too long',
    },
    { user  => 'admin',
      args  => { name => 'Another Product', version => PROD_VERSION,
                 description => DESCRIPTION },
      error => 'already exists',
      test  => 'Name to Product.create already exists',
    },
    { user  => 'admin',
      args  => { name => 'aNoThEr Product', version => PROD_VERSION,
                 description => DESCRIPTION },
      error => 'differs from existing product',
      test  => 'Name to Product.create already exists but with a different case',
    },
);

# FIXME: Should be: if (classifications enabled).
#        But there is currently now way to query the value of a parameter via WS.
if (0) {
    push(@tests,
        { user  => 'admin',
          args  => { name => random_string(20), version => PROD_VERSION,
                     description => DESCRIPTION, has_unconfirmed => 1,
                     classification => '', default_milestone => '2.0',
                     is_open => 1, create_series => 1 },
          error => 'You must select/enter a classification',
          test  => 'Passing an empty classification to Product.create fails',
        },
        { user  => 'admin',
          args  => { name => random_string(20), version => PROD_VERSION,
                     description => DESCRIPTION, has_unconfirmed => 1,
                     classification => random_string(10), default_milestone => '2.0',
                     is_open => 1, create_series => 1 },
          error => 'You must select/enter a classification',
          test  => 'Passing an invalid classification to Product.create fails',
        },
    )
}

$jsonrpc_get->bz_call_fail('Product.create',
    { name => random_string(20), version => PROD_VERSION,
      description => 'Created with JSON-RPC via GET' },
    'must use HTTP POST', 'Product.create fails over GET');

foreach my $rpc ($xmlrpc, $jsonrpc) {
    # Tests which work must be called from here,
    # to avoid creating twice the same product.
    my @all_tests = (@tests,
        { user  => 'admin',
          args  => { name => random_string(20), version => PROD_VERSION,
                     description => DESCRIPTION },
          test  => 'Passing the name, description and version only works',
        },
        { user  => 'admin',
          args  => { name => random_string(20), version => PROD_VERSION,
                     description => DESCRIPTION, has_unconfirmed => 1,
                     classification => 'Class2_QA', default_milestone => '2.0',
                     is_open => 1, create_series => 1 },
          test  => 'Passing all arguments works',
        },
        { user  => 'admin',
          args  => { name => random_string(20), version => PROD_VERSION,
                     description => DESCRIPTION, has_unconfirmed => 0,
                     classification => 'Class2_QA', default_milestone => '2.0',
                     is_open => 0, create_series => 0 },
          test  => 'Passing null values works',
        },
        { user  => 'admin',
          args  => { name => random_string(20), version => PROD_VERSION,
                     description => DESCRIPTION, has_unconfirmed => 1,
                     classification => 'Class2_QA', default_milestone => '',
                     is_open => 1, create_series => 1 },
          test  => 'Passing an empty default milestone works (falls back to "---")',
        },
    );
    $rpc->bz_run_tests(tests => \@all_tests, method => 'Product.create',
                       post_success => \&post_success);
}
