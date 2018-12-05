#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use File::Basename;
use File::Spec;

BEGIN {
  require lib;
  my $dir = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
  lib->import(
    $dir,
    File::Spec->catdir($dir, 'lib'),
    File::Spec->catdir($dir, qw(local lib perl5))
  );
}

use Bugzilla::DaemonControl qw(catch_signal);
use Future;
use IO::Async::Loop;
use IO::Async::Protocol::LineStream;
use IO::Handle;

$ENV{LOGGING_PORT} //= 5880;

STDOUT->autoflush(1);

my $loop      = IO::Async::Loop->new;
my $on_stream = sub {
  my ($stream) = @_;
  my $protocol = IO::Async::Protocol::LineStream->new(
    transport    => $stream,
    on_read_line => sub {
      my ($self, $line) = @_;
      say $line;
    },
  );
  $loop->add($protocol);
};
my @signals = qw( TERM INT KILL );

$loop->listen(
  host      => '127.0.0.1',
  service   => $ENV{LOGGING_PORT},
  socktype  => 'stream',
  on_stream => $on_stream,
)->get;

exit Future->wait_any(map { catch_signal($_, 0) } @signals)->get;
