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
use Mojo::File qw(path);
use File::Spec::Functions qw(catfile);

sub _new_bloom_filter {
  my ($n) = @_;
  my $p   = 0.01;
  my $m   = $n * abs(log $p) / log(2)**2;
  my $k   = $m / $n * log(2);
  return Algorithm::BloomFilter->new($m, $k);
}

sub _file {
  my ($name, $type) = @_;

  my $datadir = bz_locations->{datadir};

  return path(catfile($datadir, "$name.$type"));
}

sub populate {
  my ($class, $name) = @_;
  my $memcached = Bugzilla->memcached;
  my @items     = split(/\n/, _file($name, 'list')->slurp);
  my $filter    = _new_bloom_filter(@items + 0);

  $filter->add($_) foreach @items;
  _file($name, 'bloom')->spurt($filter->serialize);
  $memcached->clear_bloomfilter({name => $name});
}

sub lookup {
  my ($class, $name) = @_;
  my $memcached   = Bugzilla->memcached;
  my $file        = _file($name, 'bloom');
  my $filter_data = $memcached->get_bloomfilter({name => $name});

  if (!$filter_data && -f $file) {
    $filter_data = $file->slurp;
    $memcached->set_bloomfilter({name => $name, filter => $filter_data});
  }

  return Algorithm::BloomFilter->deserialize($filter_data) if $filter_data;
  return undef;
}

1;
