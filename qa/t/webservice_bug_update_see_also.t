# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#################################################
# Test for xmlrpc call to Bug.update_see_also() #
#################################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use QA::Util;
use QA::Tests qw(PRIVATE_BUG_USER STANDARD_BUG_TESTS);
use Test::More tests => 117;
my ($config, $xmlrpc, $jsonrpc, $jsonrpc_get) = get_rpc_clients();

my $bug_url = 'http://landfill.bugzilla.org/bugzilla-tip/show_bug.cgi?id=100';

# update_see_also doesn't support logged-out users.
my @tests = grep { $_->{user} } @{ STANDARD_BUG_TESTS() };
foreach my $t (@tests) {
    $t->{args}->{add} = $t->{args}->{remove} = [];
}

push(@tests, (
    { user  => 'unprivileged',
      args  => { ids => ['public_bug'], add => [$bug_url] },
      error => 'only the assignee or reporter of the bug, or a user',
      test  => 'Unprivileged user cannot add a URL to a bug',
    },

    { user  => 'admin',
      args  => { ids => ['public_bug'], add => ['asdfasdfasdf'] },
      error => 'asdf',
      test  => 'Admin cannot add an invalid URL',
    },
    { user => 'admin',
      args => { ids => ['public_bug'], remove => ['asdfasdfasdf'] },
      test => 'Invalid URL silently ignored',
    },

    { user => 'admin',
      args => { ids => ['public_bug'], add => [$bug_url] },
      test => 'Admin can add a URL to a public bug',
    },
    { user  => 'unprivileged',
      args  => { ids => ['public_bug'], remove => [$bug_url] },
      error => 'only the assignee or reporter of the bug, or a user',
      test  => 'Unprivileged user cannot remove a URL from a bug',
    },
    { user => 'admin',
      args => { ids => ['public_bug'], remove => [$bug_url] },
      test => 'Admin can remove a URL from a public bug',
    },

    { user => PRIVATE_BUG_USER,
      args => { ids => ['private_bug'], add => [$bug_url] },
      test => PRIVATE_BUG_USER . ' can add a URL to a private bug',
    },
    { user => PRIVATE_BUG_USER,
      args => { ids => ['private_bug'], remove => [$bug_url] },
      test => PRIVATE_BUG_USER . ' can remove a URL from a private bug',
    },

));

sub post_success {
    my ($call, $t) = @_;
    isa_ok($call->result->{changes}, 'HASH', "Changes");
}

$jsonrpc_get->bz_call_fail('Bug.update_see_also',
    { ids => ['public_bug'], add => [$bug_url] },
    'must use HTTP POST', 'update_see_also fails over GET');

foreach my $rpc ($jsonrpc, $xmlrpc) {
    $rpc->bz_run_tests(tests => \@tests, method => 'Bug.update_see_also',
                       post_success => \&post_success);
}
