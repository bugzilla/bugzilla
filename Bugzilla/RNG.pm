# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::RNG;

use 5.14.0;
use strict;
use warnings;

use parent qw(Exporter);
use Bugzilla::Constants qw(ON_WINDOWS);

use Math::Random::ISAAC;
use if ON_WINDOWS, 'Win32::API';

our $RNG;
our @EXPORT_OK = qw(rand srand irand);

# ISAAC, a 32-bit generator, should only be capable of generating numbers
# between 0 and 2^32 - 1. We want _to_float to generate numbers possibly
# including 0, but always less than 1.0. Dividing the integer produced
# by irand() by this number should do that exactly.
use constant DIVIDE_BY => 2**32;

# How many bytes of seed to read.
use constant SEED_SIZE => 16;    # 128 bits.

#################
# Windows Stuff #
#################

# For some reason, BOOLEAN doesn't work properly as a return type with
# Win32::API.
use constant RTLGENRANDOM_PROTO => <<END;
INT SystemFunction036(
  PVOID RandomBuffer,
  ULONG RandomBufferLength
)
END

#################
# RNG Functions #
#################

sub rand (;$) {
  my ($limit) = @_;
  my $int = irand();
  return _to_float($int, $limit);
}

sub irand (;$) {
  my ($limit) = @_;
  Bugzilla::RNG::srand() if !defined $RNG;
  my $int = $RNG->irand();
  if (defined $limit) {

    # We can't just use the mod operator because it will bias
    # our output. Search for "modulo bias" on the Internet for
    # details. This is slower than mod(), but does not have a bias,
    # as demonstrated by Math::Random::Secure's uniform.t test.
    return int(_to_float($int, $limit));
  }
  return $int;
}

sub srand (;$) {
  my ($value) = @_;

  # Remove any RNG that might already have been made.
  $RNG = undef;
  my %args;
  if (defined $value) {
    $args{seed} = $value;
  }
  $RNG = _create_rng(\%args);
}

sub _to_float {
  my ($integer, $limit) = @_;
  $limit ||= 1;
  return ($integer / DIVIDE_BY) * $limit;
}

##########################
# Seed and PRNG Creation #
##########################

sub _create_rng {
  my ($params) = @_;

  if (!defined $params->{seed}) {
    $params->{seed} = _get_seed();
  }

  _check_seed($params->{seed});

  my @seed_ints = unpack('L*', $params->{seed});

  my $rng = Math::Random::ISAAC->new(@seed_ints);

  # It's faster to skip the frontend interface of Math::Random::ISAAC
  # and just use the backend directly. However, in case the internal
  # code of Math::Random::ISAAC changes at some point, we do make sure
  # that the {backend} element actually exists first.
  return $rng->{backend} ? $rng->{backend} : $rng;
}

sub _check_seed {
  my ($seed) = @_;
  if (length($seed) < 8) {
    warn "Your seed is less than 8 bytes (64 bits). It could be" . " easy to crack";
  }

  # If it looks like we were seeded with a 32-bit integer, warn the
  # user that they are making a dangerous, easily-crackable mistake.
  elsif (length($seed) <= 10 and $seed =~ /^\d+$/) {
    warn "RNG seeded with a 32-bit integer, this is easy to crack";
  }
}

sub _get_seed {
  return _windows_seed() if ON_WINDOWS;

  if (-r '/dev/urandom') {
    return _read_seed_from('/dev/urandom');
  }

  return _read_seed_from('/dev/random');
}

sub _read_seed_from {
  my ($from) = @_;

  open(my $fh, '<', $from) or die "$from: $!";
  my $buffer;
  read($fh, $buffer, SEED_SIZE);
  if (length($buffer) < SEED_SIZE) {
    die "Could not read enough seed bytes from $from, got only " . length($buffer);
  }
  close $fh;
  return $buffer;
}

sub _windows_seed {
  my ($major, $minor) = (Win32::GetOSVersion())[1, 2];
  if ($major < 5 || ($major == 5 and $minor == 0)) {
    die 'Bugzilla does not support versions of Windows before Windows XP';
  }

  my $rtlgenrand = Win32::API->new('advapi32', RTLGENRANDOM_PROTO);
  if (!defined $rtlgenrand) {
    die "Could not import RtlGenRand: $^E";
  }
  my $buffer = chr(0) x SEED_SIZE;
  my $result = $rtlgenrand->Call($buffer, SEED_SIZE);
  if (!$result) {
    die "RtlGenRand failed: $^E";
  }
  return $buffer;
}

1;

=head1 B<Methods in need of POD>

=over

=item srand

=item rand

=item irand

=back
