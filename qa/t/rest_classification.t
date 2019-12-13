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

use Test::More tests => 6;
use QA::REST;

my $rest   = get_rest_client();
my $config = $rest->bz_config;
my $args   = {api_key => $config->{admin_user_api_key}};

# Admins can always access classifications, even when they are disabled.
my $class = $rest->call('classification/1', $args)->{classifications}->[0];
ok($class->{id},
      "Admin found classification '"
    . $class->{name}
    . "' with the description '"
    . $class->{description}
    . "'");
my @products = sort map { $_->{name} } @{$class->{products}};
ok(scalar(@products),
  scalar(@products) . ' product(s) found: ' . join(', ', @products));

$class = $rest->call('classification/Class2_QA', $args)->{classifications}->[0];
ok($class->{id},
      "Admin found classification '"
    . $class->{name}
    . "' with the description '"
    . $class->{description}
    . "'");
@products = sort map { $_->{name} } @{$class->{products}};
ok(scalar(@products),
  scalar(@products) . ' product(s) found: ' . join(', ', @products));

# When classifications are enabled, everybody can query classifications...
# ... including logged-out users.
$class = $rest->call('classification/1')->{classifications}->[0];
ok($class->{id},
  'Logged-out users can access classification ' . $class->{name});

# ... and non-admins.
$class = $rest->call('classification/1',
  {api_key => $config->{editbugs_user_api_key}})->{classifications}->[0];
ok($class->{id}, 'Non-admins can access classification ' . $class->{name});
