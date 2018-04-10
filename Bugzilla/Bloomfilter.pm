# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Bloomfilter;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants;
use Algorithm::BloomFilter;
use File::Slurper qw(write_binary read_binary read_lines);
use File::Spec::Functions qw(catfile);

sub _new_bloom_filter {
    my ($n) = @_;
    my $p = 0.01;
    my $m = $n * abs(log $p) / log(2) ** 2;
    my $k = $m / $n * log(2);
    return Algorithm::BloomFilter->new($m, $k);
}

sub _filename {
    my ($name, $type) = @_;

    my $datadir = bz_locations->{datadir};

    return catfile($datadir, "$name.$type");
}

sub populate {
    my ($class, $name) = @_;
    my $memcached = Bugzilla->memcached;
    my @items     = read_lines(_filename($name, 'list'));
    my $filter    = _new_bloom_filter(@items + 0);

    $filter->add($_) foreach @items;
    write_binary(_filename($name, 'bloom'), $filter->serialize);
    $memcached->clear_bloomfilter({name => $name});
}

sub lookup {
    my ($class, $name) = @_;
    my $memcached   = Bugzilla->memcached;
    my $filename    = _filename($name, 'bloom');
    my $filter_data = $memcached->get_bloomfilter( { name => $name } );

    if (!$filter_data && -f $filename) {
        $filter_data = read_binary($filename);
        $memcached->set_bloomfilter({ name => $name, filter => $filter_data });
    }

    return Algorithm::BloomFilter->deserialize($filter_data) if $filter_data;
    return undef;
}

1;
