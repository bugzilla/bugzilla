# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##########################################
# Test for xmlrpc call to Group.create() #
##########################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Test::More tests => 77;
use QA::Util;

use constant DESCRIPTION => 'Group created by Group.create';

sub post_success {
    my $call = shift;
    my $gid = $call->result->{id};
    ok($gid, "Got a non-zero group ID: $gid");
}

my ($config, $xmlrpc, $jsonrpc, $jsonrpc_get) = get_rpc_clients();

my @tests = (
    { args  => { name => random_string(20), description => DESCRIPTION },
      error => 'You must log in',
      test  => 'Logged-out user cannot call Group.create',
    },
    { user  => 'unprivileged',
      args  => { name => random_string(20), description => DESCRIPTION },
      error => 'you are not authorized',
      test  => 'Unprivileged user cannot call Group.create',
    },
    { user  => 'admin',
      args  => { description => DESCRIPTION },
      error => 'You must enter a name',
      test  => 'Missing name to Group.create',
    },
    { user  => 'admin',
      args  => { name => random_string(20) },
      error => 'You must enter a description',
      test  => 'Missing description to Group.create',
    },
    { user  => 'admin',
      args  => { name => '', description => DESCRIPTION },
      error => 'You must enter a name',
      test  => 'Name to Group.create cannot be empty',
    },
    { user  => 'admin',
      args  => { name => random_string(20), description => '' },
      error => 'You must enter a description',
      test  => 'Description to Group.create cannot be empty',
    },
    { user  => 'admin',
      args  => { name => 'canconfirm', description => DESCRIPTION },
      error => 'already exists',
      test  => 'Name to Group.create already exists',
    },
    { user  => 'admin',
      args  => { name => 'caNConFIrm', description => DESCRIPTION },
      error => 'already exists',
      test  => 'Name to Group.create already exists but with a different case',
    },
    { user  => 'admin',
      args  => { name => random_string(20), description => DESCRIPTION,
                 user_regexp => '\\'},
      error => 'The regular expression you entered is invalid',
      test  => 'The regular expression passed to Group.create is invalid',
    },
);

$jsonrpc_get->bz_call_fail('Group.create',
    { name => random_string(20), description => 'Created with JSON-RPC via GET' },
    'must use HTTP POST', 'Group.create fails over GET');

foreach my $rpc ($xmlrpc, $jsonrpc) {
    # Tests which work must be called from here,
    # to avoid creating twice the same group.
    my @all_tests = (@tests,
        { user  => 'admin',
          args  => { name => random_string(20), description => DESCRIPTION },
          test  => 'Passing the name and description only works',
        },
        { user  => 'admin',
          args  => { name => random_string(20), description => DESCRIPTION,
                     user_regexp => '\@foo.com$', is_active => 1,
                     icon_url => 'http://www.bugzilla.org/favicon.ico' },
          test  => 'Passing all arguments works',
        },
    );
    $rpc->bz_run_tests(tests => \@all_tests, method => 'Group.create',
                       post_success => \&post_success);
}
