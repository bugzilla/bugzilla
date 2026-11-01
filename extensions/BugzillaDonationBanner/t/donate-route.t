#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.14.0;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Cwd qw(abs_path);
use IPC::Open3;
use IO::Select;
use Symbol qw(gensym);
use Test::More;

my $root = abs_path('.');
my $script = 'extensions/BugzillaDonationBanner/bin/donate.cgi';
my $script_name = "/$script";

sub request {
  my ($method) = @_;
  my $stderr = gensym();
  my ($stdin, $stdout);

  local %ENV = %ENV;
  delete @ENV{qw(PERL5LIB PERL5OPT)};
  @ENV{qw(REQUEST_METHOD GATEWAY_INTERFACE SERVER_PROTOCOL SERVER_NAME
    HTTP_HOST SERVER_PORT REMOTE_ADDR SCRIPT_NAME REQUEST_URI QUERY_STRING
    CONTENT_LENGTH BUGZILLA_DISABLE_HOSTAGE)}
    = ($method, 'CGI/1.1', 'HTTP/1.1', 'bugzilla.test', 'bugzilla.test',
    80, '127.0.0.1', $script_name, $script_name, '', 0, 1);

  my $pid = open3(
    $stdin, $stdout, $stderr,
    $^X, '-T', "-I$root", "-I$root/lib", "-I$root/local/lib/perl5", '-e',
    q{
      use Bugzilla;
      use Bugzilla::Extension;
      Bugzilla::Extension->load(
        'extensions/BugzillaDonationBanner/Extension.pm',
        'extensions/BugzillaDonationBanner/Config.pm'
      );
      my $script = shift @ARGV;
      $script =~ m{^([\w./-]+)$} or die 'invalid script path';
      do $1 or die $@ || $!;
    },
    "$root/$script"
  );
  close $stdin;

  my $select = IO::Select->new($stdout, $stderr);
  my ($output, $errors) = ('', '');
  while (my @ready = $select->can_read) {
    for my $handle (@ready) {
      my $count = sysread($handle, my $buffer, 4096);
      if (!$count) {
        $select->remove($handle);
        close $handle;
      }
      elsif (fileno($handle) == fileno($stdout)) {
        $output .= $buffer;
      }
      else {
        $errors .= $buffer;
      }
    }
  }
  waitpid($pid, 0);
  return ($output, $errors, $? >> 8);
}

for my $method (qw(GET HEAD PUT DELETE)) {
  subtest "$method is rejected" => sub {
    my ($output, $errors, $exit) = request($method);
    is($exit, 0, 'CGI exits normally') or diag($errors);
    like($output, qr/^Status:\s*405 Method Not Allowed\r?$/mi,
      'returns 405 Method Not Allowed');
    like($output, qr/^Allow:\s*POST\r?$/mi, 'allows only POST');
  };
}

done_testing;