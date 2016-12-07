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

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Config qw( :admin );
use Bugzilla::Constants;
use Bugzilla::Install::Localconfig;

use File::Slurp;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $localconfig =  Bugzilla::Install::Localconfig::read_localconfig();

my ($param_name, $param_value) = @ARGV;
die "Syntax: $0 param_name param_value\n" unless defined($param_value);
die "Invalid param name: $param_name\n" unless exists $localconfig->{$param_name};

if ($localconfig->{$param_name} ne $param_value) {
    my @file = read_file('localconfig');
    my $updated = 0;
    foreach my $line (@file) {
        next unless $line =~ /^\s*\$([\w_]+)\s*=\s*'([^']*)'/;
        my ($name, $value) = ($1, $2);
        if ($name eq $param_name && $value ne $param_value) {
            print "setting '$name' to '$param_value'\n";
            $line = "\$$name = '$param_value';\n";
            $updated = 1;
        }
    }
    write_file('localconfig', @file) if $updated;
} else {
    print "'$param_name' is already '$param_value'\n";
}
