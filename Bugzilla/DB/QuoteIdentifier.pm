# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::DB::QuoteIdentifier;

use 5.14.0;
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

=head1 METHODS

=head2 TIEHASH

This class can be used as a tied hash, which is only done to allow quoting identifiers inside double-quoted strings.

Exmaple:

    my $qi = Bugzilla->dbh->qi;
    my $sql = "SELECT $qi->{bug_id} FROM $qi->{bugs}";

=head2 FETCH

Returns the quoted identifier for the given key, this just calls C<quote_identifier> on the database handle.

=head2 FIRSTKEY

This returns nothing, as this tied hash has no keys or values.

=head2 FIRSTVALUE

This returns nothing, as this tied hash has no keys or values.

=head2 EXISTS

This always returns true, as this tied hash has no keys or values but technically every key exists.

=head2 DELETE

This always returns true, as this tied hash has no keys or values but technically every key can be deleted.

=head2 db

This is a weak reference to the database handle that is used to quote identifiers.

=head1 SEE ALSO

L<Bugzilla::DB::Schema>

=cut

