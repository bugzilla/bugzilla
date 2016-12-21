# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#########################################################
# Test for xmlrpc call to User.offer_account_by_email() #
#########################################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use QA::Util;
use Test::More tests => 29;
my ($config, $xmlrpc, $jsonrpc, $jsonrpc_get) = get_rpc_clients();

# These are the characters that are actually invalid per RFC.
use constant INVALID_EMAIL => '()[]\;:,<>@webservice.test';

sub new_login {
    return 'requested_' . random_string() . '@webservice.test';
}

$jsonrpc_get->bz_call_fail('User.offer_account_by_email',
    { email => new_login() },
    'must use HTTP POST', 'offer_account_by_email fails over GET');

# Have to wrap @tests in the foreach so that new_login returns something
# different each time.
foreach my $rpc ($jsonrpc, $xmlrpc) {
    my @tests = (
        # Login name checks.
        { args  => { },
          error => "argument was not set",
          test  => 'Leaving out email argument fails',
        },
        { args  => { email => '' },
          error => "argument was not set",
          test  => "Passing an empty email argument fails",
        },
        { args  => { email => INVALID_EMAIL },
          error => "didn't pass our syntax checking",
          test  => 'Invalid email address fails',
        },
        { args  => { email => $config->{unprivileged_user_login} },
          error => "There is already an account",
          test  => 'Trying to use an existing login name fails',
        },

        { args => { email => new_login() },
          test => 'Valid, non-existing email passes.',
        },
    );

    $rpc->bz_run_tests(tests => \@tests,
                       method => 'User.offer_account_by_email');
}
