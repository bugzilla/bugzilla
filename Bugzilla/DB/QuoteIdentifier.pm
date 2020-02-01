# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::DB::QuoteIdentifier;

use 5.10.1;
use Moo;

has 'db' => (
  is       => 'ro',
  weak_ref => 1,
  required => 1,
);

sub TIEHASH {
  my ($class, @args) = @_;

  return $class->new(@args);
}

sub FETCH {
  my ($self, $key) = @_;

  return $self->db->quote_identifier($key);
}

sub FIRSTKEY {
  return;
}

sub FIRSTVALUE {
  return;
}

sub EXISTS {
  return 1
}

sub DELETE {
  return 1
}

1;

__END__

=head1 NAME

Bugzilla::DB::QuoteIdentifier

=head1 SYNOPSIS

  my %q;
  tie %q, 'Bugzilla::DB::QuoteIdentifier', db => Bugzilla->dbh;

  is("this is $q{something}", 'this is ' . Bugzilla->dbh->quote_identifier('something'));

=head1 DESCRIPTION

Bugzilla has many strings with bare sql column names or table names. Sometimes,
as in the case of MySQL 8, formerly unreserved keywords can become reserved.

This module provides a shortcut for quoting identifiers in strings by way of overloading a hash
so that we can easily call C<quote_identifier> inside double-quoted strings.

=cut

