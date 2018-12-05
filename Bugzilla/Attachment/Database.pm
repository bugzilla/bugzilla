# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::Database;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Util qw(trick_taint);

sub new {
  return bless({}, shift);
}

sub store {
  my ($self, $attach_id, $data) = @_;
  my $dbh = Bugzilla->dbh;
  my $sth = $dbh->prepare(
    "INSERT INTO attach_data (id, thedata) VALUES ($attach_id, ?)");
  trick_taint($data);
  $sth->bind_param(1, $data, $dbh->BLOB_TYPE);
  $sth->execute();
}

sub retrieve {
  my ($self, $attach_id) = @_;
  my $dbh = Bugzilla->dbh;
  my ($data)
    = $dbh->selectrow_array("SELECT thedata FROM attach_data WHERE id = ?",
    undef, $attach_id);
  return $data;
}

sub remove {
  my ($self, $attach_id) = @_;
  my $dbh = Bugzilla->dbh;
  $dbh->do("DELETE FROM attach_data WHERE id = ?", undef, $attach_id);
}

sub exists {
  my ($self, $attach_id) = @_;
  my $dbh = Bugzilla->dbh;
  my ($exists) = $dbh->selectrow_array("SELECT 1 FROM attach_data WHERE id = ?",
    undef, $attach_id);
  return !!$exists;
}

1;
