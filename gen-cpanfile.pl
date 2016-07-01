#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This file has detailed POD docs, do "perldoc checksetup.pl" to see them.

######################################################################
# Initialization
######################################################################

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Getopt::Long qw(:config gnu_getopt);

if (-f "MYMETA.json") {
    eval {
        require CPAN::Meta;
        require Module::CPANfile;

        my (@with_feature, @without_feature);
        my $with_all_features = 0;
        GetOptions(
            'with-all-features|A!' => \$with_all_features,
            'with-feature|D=s@'    => \@with_feature,
            'without-feature|U=s@' => \@without_feature
        );


        my $meta = CPAN::Meta->load_file("MYMETA.json");

        my @phases = qw(configure build test develop runtime);
        my @types  = qw(requires recommends suggests conflicts);

        my %features;
        if ($with_all_features) {
            $features{$_->identifier} = 1 foreach ($meta->features);
        }
        $features{$_} = 1 foreach @with_feature;
        $features{$_} = 0 foreach @without_feature;
        my @features = grep { $features{$_} } keys %features;

        my $prereqs = $meta->effective_prereqs(\@features)->as_string_hash;
        my $filtered = {};

        while (my($phase, $types) = each %$prereqs) {
            while (my($type, $reqs) = each %$types) {
                $filtered->{$phase}{$type} = $reqs;
            }
        }

        my $cpanfile = Module::CPANfile->from_prereqs($filtered);
        open my $cpanfile_fh, '>', 'cpanfile' or die "cannot write to cpanfile: $!";
        print $cpanfile_fh $cpanfile->to_string();
        close $cpanfile_fh;
    };
    die "Unable generate cpanfile: $@\n" if $@;
}
else {
    die "MYMETA.yml is missing, cannot generate cpanfile\n";
}
