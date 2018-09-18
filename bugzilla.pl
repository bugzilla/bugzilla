#!/usr/bin/perl
use 5.10.1;
use strict;
use warnings;

use File::Basename qw(basename dirname);
use File::Spec::Functions qw(catdir);
use Cwd qw(realpath);

BEGIN {
    require lib;
    my $dir = realpath( dirname(__FILE__) );
    lib->import( $dir, catdir( $dir, 'lib' ), catdir( $dir, qw(local lib perl5) ) );
}
use Mojolicious::Commands;

$ENV{MOJO_LISTEN} ||= $ENV{PORT} ? "http://*:$ENV{PORT}" : "http://*:3001";

# Start command line interface for application
Mojolicious::Commands->start_app('Bugzilla::Quantum');
