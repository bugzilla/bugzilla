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
use autodie;
use lib qw(. lib local/lib/perl5);
use IO::Handle;
use Test::More;

my $dockerfile = 'Dockerfile';
my $ci_config = '.circleci/config.yml';

my $base;
open my $dockerfile_fh, '<', $dockerfile;
while (my $line = readline $dockerfile_fh) {
    chomp $line;
    if ($line =~ /^FROM\s+(\S+)/ms) {
        $base = $1;
        last;
    }
}
close $dockerfile_fh;

my ($image, $version) = split(/:/ms, $base, 2);
is($image, 'mozillabteam/bmo-slim', "base image is mozillabteam/bmo-slim");
like($version, qr/\d{4}\d{2}\d{2}\.\d+/ms, "version is YYYYMMDD.x");

my $regex = qr{
    \Q$image\E
    :
    (?!\Q$version\E)
    (\d{4}\d{2}\d{2}\.\d+)
}msx;

open my $ci_config_fh, '<', $ci_config;
while (my $line = readline $ci_config_fh) {
    chomp $line;
    if ($line =~ /($regex)/ms) {
        my $ln = $ci_config_fh->input_line_number;
        fail("found docker image $1, expected $base in $ci_config line $ln");
    }
    pass("Forbidden version not found");
}
close $ci_config_fh;

done_testing;