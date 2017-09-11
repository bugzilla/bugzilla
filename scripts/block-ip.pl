#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::ModPerl::BlockIP;
use Getopt::Long;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $unblock;
GetOptions('unblock' => \$unblock);

pod2usage("No IPs given") unless @ARGV;

if ($unblock) {
    Bugzilla::ModPerl::BlockIP->unblock_ip($_) for @ARGV;
} else {
    Bugzilla::ModPerl::BlockIP->block_ip($_) for @ARGV;
}

=head1 NAME

block-ip.pl -- block or unlock ip addresses from Bugzilla's IP block list

=head1 SYNOPSIS

block-ip.pl [--unblock] ip1 [ip2 ...]

    Options:
        --unblock   instead of blocking, unblock the listed IPs

=head1 OPTIONS

=over 4

=item B<--unblock>

If passed, the IPs will be unblocked instead of blocked. Use this to remove IPs from the blocklist.

=back

=head1 DESCRIPTION

This is just a simple CLI inteface to L<Bugzilla::ModPerl::BlockIP>.
