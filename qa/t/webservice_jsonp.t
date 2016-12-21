# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Test::More tests => 85;
use QA::Util;
my $jsonrpc_get = QA::Util::get_jsonrpc_client('GET');

my @chars = (0..9, 'A'..'Z', 'a'..'z', '_[].');

our @tests = (
    { args => { callback => join('', @chars) },
      test => 'callback accepts all legal characters.' },
);
foreach my $char (qw(! ~ ` @ $ % ^ & * - + = { } ; : ' " < > / ? |),
                  '(', ')', '\\', '#', ',')
{
    push(@tests,
         { args  => { callback => "a$char" },
           error => "as your 'callback' parameter",
           test  => "$char is not valid in callback" });
}

$jsonrpc_get->bz_run_tests(method => 'Bugzilla.version', tests => \@tests);
