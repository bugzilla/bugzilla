# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Role::FlattenToHash;

use 5.10.1;
use strict;
use warnings;
use Role::Tiny;
use Scalar::Util qw(blessed);

requires 'DB_TABLE', '_get_db_columns';

my $_error = sub { die "cannot determine attribute name from $_[0]\n" };

sub _get_db_keys {
  my ($self, $object) = @_;
  my $class   = blessed($self) // $self;
  my $table   = $class->DB_TABLE;
  my @columns = $class->_get_db_columns;
  my $re      = qr{
    ^\s*(?<name>\w+)\s*$
    | ^\s*\Q$table.\E(?<name>\w+)\s*$
    | \s+AS\s+(?<name>\w+)\s*$
  }six;

  return map { $_ =~ $re ? $+{name} : $_error->($_) } @columns;
}

sub flatten_to_hash {
  my ($self) = @_;
  my %hash;
  my @keys = $self->_get_db_keys();
  @hash{@keys} = @$self{@keys};
  return \%hash;
}

1;
