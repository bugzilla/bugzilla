# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.10.1;
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );
use IO::Async::Process;
use IO::Async::Loop;
use IO::Async::Timer::Countdown;
use Test::More;

use ok 'Bugzilla::DaemonControl', qw(catch_signal);

my $loop = IO::Async::Loop->new;
my $signal_test_out = '';
my $signal_test = IO::Async::Process->new(
    code => sub {
        my $f = catch_signal("TERM", 42);
        say $f->isa('Future') ? "I have a Future" : '';
        my $val = $f->get;
        say "Got $val from TERM";
        sleep 30;
        say "I Failed My Mission";
    },
    stdout => { into => \$signal_test_out },
    on_finish => sub {
        $loop->stop;
    },
    on_exception => sub {
        diag "@_";
        fail("got exception");
        $loop->stop;
    }
);
diag "starting signal test";
$loop->add($signal_test);
ok( $signal_test->is_running, "signal test is running");

my $send_first_term = IO::Async::Timer::Countdown->new(
    delay => 5,
    on_expire => sub {
        diag "sending first TERM";
        ok($signal_test->is_running, "signal test is still running");
        $signal_test->kill('TERM');
    }
);

$send_first_term->start;
$loop->add($send_first_term);

my $send_second_term = IO::Async::Timer::Countdown->new(
    delay => 10,
    on_expire => sub {
        diag "sending second TERM";
        ok($signal_test->is_running, "signal test is still running");
        $signal_test->kill('TERM');
    }
);
$send_second_term->start;

$loop->add($send_second_term);

my $timeout = IO::Async::Timer::Countdown->new(
    delay => 60,
    on_expire => sub {
        fail("test ran for too long");
        $loop->stop;
    },
);
$timeout->start;

$loop->add($timeout);

$loop->run;

diag $signal_test_out;
like($signal_test_out, qr/I have a Future/, "catch_signal() returned a future");
like($signal_test_out, qr/Got 42 from TERM/, "catch_signal() returned the right value when done");
unlike($signal_test_out, qr/I Failed My Mission/, "catch_signal() only happened once");

done_testing();