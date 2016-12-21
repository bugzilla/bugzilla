# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#########################################
# Test for xmlrpc call to Bug.history() #
#########################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use QA::Util;
use QA::Tests qw(STANDARD_BUG_TESTS);
use Test::More tests => 114;
my ($config, @clients) = get_rpc_clients();

sub post_success {
    my ($call, $t) = @_;
    is(scalar @{ $call->result->{bugs} }, 1, "Got exactly one bug");
    isa_ok($call->result->{bugs}->[0]->{history}, 'ARRAY', "Bug's history");
}

foreach my $rpc (@clients) {
    $rpc->bz_run_tests(tests => STANDARD_BUG_TESTS,
                       method => 'Bug.history', post_success => \&post_success);
}
