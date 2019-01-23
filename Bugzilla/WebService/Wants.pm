# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::Wants;
use 5.10.1;
use Moo;
use MooX::StrictConstructor;

use Types::Standard qw(ArrayRef Str);
use List::MoreUtils qw(any none);

has 'cache' => (is => 'ro', required => 1);
has ['exclude_fields', 'include_fields'] =>
  (is => 'ro', isa => ArrayRef [Str], default => sub { return [] });
has ['include',      'exclude']      => (is => 'lazy');
has ['include_type', 'exclude_type'] => (is => 'lazy');

sub _build_include {
  my ($self) = @_;
  return {map { $_ => 1 } grep { not m/^_/ } @{$self->include_fields}};
}

sub _build_exclude {
  my ($self) = @_;
  return {map { $_ => 1 } grep { not m/^_/ } @{$self->exclude_fields}};
}

sub _build_include_type {
  my ($self) = @_;
  my @include = @{$self->include_fields};
  if (@include) {
    return {map { substr($_, 1) => 1 } grep {m/^_/} @include};
  }
  else {
    return {default => 1};
  }
}

sub _build_exclude_type {
  my ($self) = @_;
  return {map { substr($_, 1) => 1 } grep {m/^_/} @{$self->exclude_fields}};
}

sub includes {
  my ($self) = @_;
  return keys %{$self->include};
}

sub excludes {
  my ($self) = @_;
  return keys %{$self->exclude};
}

sub include_types {
  my ($self) = @_;
  return keys %{$self->include_type};
}

sub exclude_types {
  my ($self) = @_;
  return keys %{$self->exclude_type};
}

sub is_empty {
  my ($self) = @_;
  return @{$self->include_fields} == 0 && @{$self->exclude_fields} == 0;
}

sub is_specific {
  my ($self) = @_;
  return !$self->is_empty && !$self->exclude_types && !$self->include_types;
}

sub match {
  my ($self, $field, $types, $prefix) = @_;

  # Since this is operation is resource intensive, we will cache the results
  # This assumes that $params->{*_fields} doesn't change between calls
  my $cache = $self->cache;
  $field = "${prefix}.${field}" if $prefix;

  my $include = $self->include;
  my $exclude = $self->exclude;

  if (exists $cache->{$field}) {
    return $cache->{$field};
  }

  # Mimic old behavior if no types provided
  $types //= ['default'];
  $types = [$types] if $types && !ref $types;

  # Explicit inclusion/exclusion
  return $cache->{$field} = 0 if $exclude->{$field};
  return $cache->{$field} = 1 if $include->{$field};

  my $include_type = $self->include_type;
  my $exclude_type = $self->exclude_type;

  # If the user has asked to include all or exclude all
  return $cache->{$field} = 0 if $exclude_type->{all};
  return $cache->{$field} = 1 if $include_type->{all};

  # If the user has not asked for any fields specifically or if the user has asked
  # for one or more of the field's types (and not excluded them)
  foreach my $type (@$types) {
    return $cache->{$field} = 0 if $exclude_type->{$type};
    return $cache->{$field} = 1 if $include_type->{$type};
  }

  my $wants = 0;
  if ($prefix) {

    # Include the field if the parent is include (and this one is not excluded)
    $wants = 1 if $include->{$prefix};
  }
  else {
    # We want to include this if one of the sub keys is included
    my $key = $field . '.';
    my $len = length($key);
    $wants = 1 if any { substr($_, 0, $len) eq $key } keys %$include;
  }

  return $cache->{$field} = $wants;
}

1;
