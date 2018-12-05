#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;

use File::Basename;
use File::Spec;

BEGIN {
  require lib;
  my $dir = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), ".."));
  lib->import(
    $dir,
    File::Spec->catdir($dir, "lib"),
    File::Spec->catdir($dir, qw(local lib perl5))
  );
  chdir($dir);
}

use Bugzilla;
BEGIN { Bugzilla->extensions }

use Bugzilla::Elastic::Indexer;
use IO::Async::Timer::Periodic;
use IO::Async::Loop;
use Time::HiRes qw(time);

use Getopt::Long qw(:config gnu_getopt);

my ($debug_sql, $progress_bar, $once);
my $verbose = 0;

GetOptions(
  'verbose|v+'   => \$verbose,
  'debug-sql'    => \$debug_sql,
  'progress-bar' => \$progress_bar,
  'once|n'       => \$once,
);

if ($progress_bar) {
  $progress_bar = eval { require Term::ProgressBar; 1 };
}

my $indexer = Bugzilla::Elastic::Indexer->new(
  $debug_sql ? (debug_sql => 1) : (),
  $progress_bar ? (progress_bar => 'Term::ProgressBar') : (),
);

my $run_time = time;
my $loop     = IO::Async::Loop->new;
my $timer    = IO::Async::Timer::Periodic->new(
  first_interval => 0,
  interval       => 15,
  reschedule     => 'skip',

  on_tick => sub {
    printf "Running after %d seconds\n", time - $run_time;
    my $start_users = time;
    say "indexing users" if $verbose;
    my $users = $indexer->bulk_load('Bugzilla::User');
    bulk_load_stats($start_users, $users) if $verbose > 1;

    my $start_bugs = time;
    say "indexing bugs" if $verbose;
    my $bugs = $indexer->bulk_load('Bugzilla::Bug');
    bulk_load_stats($start_bugs, $bugs) if $verbose > 1;

    my $start_comments = time;
    say "indexing comments" if $verbose;
    my $comments = $indexer->bulk_load('Bugzilla::Comment');
    bulk_load_stats($start_comments, $comments) if $verbose > 1;

    $loop->stop if $once;
    $run_time = time;
  },
);

$timer->start();
$loop->add($timer);
$loop->run;

sub bulk_load_stats {
  my ($start_time, $info) = @_;
  printf "    %d seconds (%d new, %d update)\n", time - $start_time,
    $info->{new}, $info->{updated};
}
