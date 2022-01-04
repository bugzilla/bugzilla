#!/bin/sh

[ -z "$BZ_DB_HOST" ] && echo "Missing Docker Environment, check docker-compose.yml" && exit -1
cd /var/www/html
apachectl start
echo "Checking database..."
cat - >/root/docker/myclient-root.cnf <<EOF
[client]
host='$BZ_DB_HOST'
port=$BZ_DB_PORT
user='root'
password='$MARIADB_ROOT_PASSWORD'
EOF
TESTSQL="show databases like '$BZ_DB_NAME'"
DBEXISTS=`echo "$TESTSQL" | mysql --defaults-file=/root/docker/myclient-root.cnf -BN`
[ -z "$DBEXISTS" ] && (
  echo "Database not found, creating..."
  CREATESQL="
CREATE DATABASE \`$BZ_DB_NAME\`;
GRANT SELECT, INSERT,
UPDATE, DELETE, INDEX, ALTER, CREATE, LOCK TABLES,
CREATE TEMPORARY TABLES, DROP, REFERENCES ON \`$BZ_DB_NAME\`.*
TO '$BZ_DB_USER'@'%' IDENTIFIED BY '$BZ_DB_PASS';
FLUSH PRIVILEGES;
"
  echo "$CREATESQL" | mysql --defaults-file=/root/docker/myclient-root.cnf -BN
)
echo "Beginning checksetup..."
perl -pi -e "
s/%%BZ_DB_HOST%%/'$BZ_DB_HOST'/;
s/%%BZ_DB_PORT%%/$BZ_DB_PORT/;
s/%%BZ_DB_NAME%%/'$BZ_DB_NAME'/;
s/%%BZ_DB_USER%%/'$BZ_DB_USER'/;
s/%%BZ_DB_PASS%%/'$BZ_DB_PASS'/;
" /root/docker/checksetup_answers.txt
perl checksetup.pl /root/docker/checksetup_answers.txt
echo "Checksetup completed."
# don't exit docker
while [ 1 ]; do sleep 1000; done
