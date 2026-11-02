#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
use strict;
use warnings;
use DBI;

my %attrs = (RaiseError => 1, PrintError => 0, AutoCommit => 1);
if ($ENV{BZ_DB_SSL}) {
  $attrs{mariadb_ssl} = 1;
  if ($ENV{BZ_DB_SSL_VERIFY}) {
    $attrs{mariadb_ssl_ca_file} = $ENV{BZ_DB_SSL_CA_FILE};
    $attrs{mariadb_ssl_verify_server_cert} = 1;
  }
}
my $dsn = "dbi:MariaDB:host=$ENV{BZ_DB_HOST};port=$ENV{BZ_DB_PORT}";
my $dbh = DBI->connect($dsn, 'root', $ENV{MARIADB_ROOT_PASSWORD}, \%attrs);
my ($exists) = $dbh->selectrow_array(
  'SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?',
  undef, $ENV{BZ_DB_NAME});
if (!defined $exists) {
  print "Database not found, creating...\n";
  my $name = $dbh->quote_identifier($ENV{BZ_DB_NAME});
  my $user = $dbh->quote($ENV{BZ_DB_USER});
  my $pass = $dbh->quote($ENV{BZ_DB_PASS});
  $dbh->do("CREATE DATABASE $name");
  $dbh->do("GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, ALTER, CREATE, "
      . "LOCK TABLES, CREATE TEMPORARY TABLES, DROP, REFERENCES ON $name.* "
      . "TO $user\@'%' IDENTIFIED BY $pass");
}
$dbh->disconnect;
