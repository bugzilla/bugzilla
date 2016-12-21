# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#########################################
# Test for xmlrpc call to User.Create() #
#########################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use QA::Util;
use Test::More tests => 75;
my ($config, $xmlrpc, $jsonrpc, $jsonrpc_get) = get_rpc_clients();

use constant NEW_PASSWORD => 'password';
use constant NEW_FULLNAME => 'WebService Created User';

use constant PASSWORD_TOO_SHORT => 'a';

# These are the characters that are actually invalid per RFC.
use constant INVALID_EMAIL => '()[]\;:,<>@webservice.test';

sub new_login {
    return 'created_' . random_string(@_) . '@webservice.test';
}

sub post_success {
    my ($call) = @_;
    ok($call->result->{id}, "Got a non-zero user id");
}

$jsonrpc_get->bz_call_fail('User.create',
    { email => new_login(), full_name => NEW_FULLNAME,
      password => '*' },
    'must use HTTP POST', 'User.create fails over GET');

# We have to wrap @tests in the foreach, because we want a different
# login for each user, separately for each RPC client. (You can't create
# two users with the same username, and XML-RPC would otherwise try to
# create the same users that JSON-RPC created.)
foreach my $rpc ($jsonrpc, $xmlrpc) {
    my @tests = (
        # Permissions checks
        { args  => { email    => new_login(), full_name => NEW_FULLNAME,
                     password => NEW_PASSWORD },
          error => "you are not authorized",
          test  => 'Logged-out user cannot call User.create',
        },
        { user  => 'unprivileged',
          args  => { email    => new_login(), full_name => NEW_FULLNAME,
                     password => NEW_PASSWORD },
          error => "you are not authorized",
          test  => 'Unprivileged user cannot call User.create',
        },

        # Login name checks.
        { user  => 'admin',
          args  => { full_name => NEW_FULLNAME, password => NEW_PASSWORD },
          error => "argument was not set",
          test  => 'Leaving out email argument fails',
        },
        { user  => 'admin',
          args  => { email    => '', full_name => NEW_FULLNAME,
                     password => NEW_PASSWORD },
          error => "argument was not set",
          test  => "Passing an empty email argument fails",
        },
        { user  => 'admin',
          args  => { email    => INVALID_EMAIL, full_name => NEW_FULLNAME,
                     password => NEW_PASSWORD },
          error =>  "didn't pass our syntax checking",
          test  => 'Invalid email address fails',
        },
        { user  => 'admin',
          args  => { email    => new_login(128), full_name => NEW_FULLNAME,
          password => NEW_PASSWORD },
          error =>  "didn't pass our syntax checking",
          test  => 'Too long (> 127 chars) email address fails',
        },
        { user  => 'admin',
          args  => { email     => $config->{unprivileged_user_login},
                     full_name => NEW_FULLNAME, password => NEW_PASSWORD },
          error =>  "There is already an account",
          test  => 'Trying to use an existing login name fails',
        },

        { user  => 'admin',
          args  => { email    => new_login(), full_name => NEW_FULLNAME,
                     password => PASSWORD_TOO_SHORT },
          error => 'password must be at least',
          test  => 'Password Too Short fails',
        },
        { user => 'admin',
          args => { email    => new_login(), full_name => NEW_FULLNAME,
                    password => NEW_PASSWORD },
          test => 'Creating a user with all arguments and correct privileges',
        },
        { user => 'admin',
          args => { email => new_login(), password => NEW_PASSWORD },
          test => 'Leaving out fullname works',
        },
        { user => 'admin',
          args => { email => new_login(), full_name => NEW_FULLNAME },
          test => 'Leaving out password works',
        },
    );

    $rpc->bz_run_tests(tests => \@tests, method => 'User.create',
                       post_success => \&post_success);
}
