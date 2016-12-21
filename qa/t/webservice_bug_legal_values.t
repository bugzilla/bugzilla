# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##############################################
# Test for xmlrpc call to Bug.legal_values() #
##############################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Test::More tests => 269;
use QA::Util;
my ($config, @clients) = get_rpc_clients();

use constant INVALID_PRODUCT_ID => -1;
use constant INVALID_FIELD_NAME => 'invalid_field';
use constant GLOBAL_FIELDS =>
    qw(bug_severity bug_status op_sys priority rep_platform resolution
       cf_qa_status cf_single_select);
use constant PRODUCT_FIELDS => qw(version target_milestone component);


my $products = $clients[0]->bz_get_products();
my $public_product = $products->{'Another Product'};
my $private_product = $products->{'QA-Selenium-TEST'};

my @all_tests;

for my $field (GLOBAL_FIELDS) {
    push(@all_tests,
         { args => { field => $field },
           test => "Logged-out user can get $field values" });
}

for my $field (PRODUCT_FIELDS) {
    my @tests = (
        { args  => { field => $field },
          error => "argument was not set",
          test  => "$field can't be accessed without a value for 'product'",
        },
        { args  => { product_id => INVALID_PRODUCT_ID, field => $field },
          error => "does not exist",
          test  => "$field cannot be accessed with an invalid product id",
        },

        { args  => { product_id => $private_product, field => $field },
          error => "you don't have access",
          test => "Logged-out user cannot access $field in private product"
        },
        { args  => { product_id => $public_product, field => $field },
          test  => "Logged-out user can access $field in a public product",
        },

        { user  => 'unprivileged',
          args  => { product_id => $private_product, field => $field },
          error => "you don't have access",
          test  => "Unprivileged user cannot access $field in private product",
        },
        { user => 'unprivileged',
          args => { product_id => $public_product, field => $field },
          test => "Logged-in user can access $field in public product",
        },

        { user => 'QA_Selenium_TEST',
          args => { product_id => $private_product, field  => $field },
          test => "Privileged user can access $field in a private product",
        },
    );

    push(@all_tests, @tests);
}

my @extra_tests = (
    { args  => { product_id => $private_product, },
      error => "requires a field argument",
      test  =>  "Passing product_id without 'field' throws an error",
    },
    { args  => { field => INVALID_FIELD_NAME },
      error => "Can't use " . INVALID_FIELD_NAME . " as a field name",
      test  => 'Invalid field name'
    },
);

push(@all_tests, @extra_tests);

sub post_success {
    my ($call) = @_;

    cmp_ok(scalar @{ $call->result->{'values'} }, '>', 0,
           'Got one or more values');
}

foreach my $rpc (@clients) {
    $rpc->bz_run_tests(tests => \@all_tests,  method => 'Bug.legal_values',
                       post_success => \&post_success);
}
