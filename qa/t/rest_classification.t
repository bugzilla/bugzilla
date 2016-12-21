# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#############################################
# Tests for REST calls in Classification.pm #
#############################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More tests => 7;
use QA::REST;

my $rest = get_rest_client();
my $config = $rest->bz_config;
my $args = { api_key => $config->{admin_user_api_key} };

my $params = $rest->call('parameters', $args)->{parameters};
my $use_class = $params->{useclassification};
ok(defined($use_class), 'Classifications are ' . ($use_class ? 'enabled' : 'disabled'));

# Admins can always access classifications, even when they are disabled.
my $class = $rest->call('classification/1', $args)->{classifications}->[0];
ok($class->{id}, "Admin found classification '" . $class->{name} . "' with the description '" . $class->{description} . "'");
my @products = sort map { $_->{name} } @{ $class->{products} };
ok(scalar(@products), scalar(@products) . ' product(s) found: ' . join(', ', @products));

$class = $rest->call('classification/Class2_QA', $args)->{classifications}->[0];
ok($class->{id}, "Admin found classification '" . $class->{name} . "' with the description '" . $class->{description} . "'");
@products = sort map { $_->{name} } @{ $class->{products} };
ok(scalar(@products), scalar(@products) . ' product(s) found: ' . join(', ', @products));

if ($use_class) {
    # When classifications are enabled, everybody can query classifications...
    # ... including logged-out users.
    $class = $rest->call('classification/1')->{classifications}->[0];
    ok($class->{id}, 'Logged-out users can access classification ' . $class->{name});
    # ... and non-admins.
    $class = $rest->call('classification/1', { api_key => $config->{editbugs_user_api_key} })->{classifications}->[0];
    ok($class->{id}, 'Non-admins can access classification ' . $class->{name});
}
else {
    # When classifications are disabled, only users in the 'editclassifications'
    # group can access this method...
    # ... logged-out users get an error.
    my $error = $rest->call('classification/1', undef, undef, MUST_FAIL);
    ok($error->{error} && $error->{code} == 900,
       'Logged-out users cannot query classifications when disabled: ' . $error->{message});
    # ... as well as non-admins.
    $error = $rest->call('classification/1', { api_key => $config->{editbugs_user_api_key} }, undef, MUST_FAIL);
    ok($error->{error} && $error->{code} == 900,
       'Non-admins cannot query classifications when disabled: ' . $error->{message});
}
