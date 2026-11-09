# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
use 5.14.0;
use strict;
use warnings;
use lib '.';
use Test::More;
use Bugzilla::DB::MariaDB;

my %params = (db_user => 'bugs', db_pass => 'password', db_host => 'db',
  db_name => 'bugs', db_port => 3306, db_sock => '');
sub attrs {
  return Bugzilla::DB::MariaDB->BUILDARGS({%params, @_})->{attrs};
}

is_deeply(attrs(db_mariadb_ssl => 1), {mariadb_ssl => 1},
  'non-strict mode requires TLS without supplying a CA');
is_deeply(attrs(db_mariadb_ssl => 1, db_mariadb_ssl_verify => 1,
    db_mysql_ssl_ca_file => '/certs/ca.pem'),
  {mariadb_ssl => 1, mariadb_ssl_verify_server_cert => 1,
    mariadb_ssl_ca_file => '/certs/ca.pem'},
  'strict mode requires TLS and verifies the server using the CA');
is_deeply(attrs(db_mariadb_ssl => 0, db_mysql_ssl_ca_file => '/certs/ca.pem'),
  {}, 'explicitly disabled TLS ignores certificate settings');
is_deeply(attrs(db_mariadb_ssl => '', db_mysql_ssl_ca_file => '/certs/ca.pem'),
  {mariadb_ssl => 1, mariadb_ssl_ca_file => '/certs/ca.pem'},
  'legacy configuration preserves certificate-driven TLS');
done_testing();
