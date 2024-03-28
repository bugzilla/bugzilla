#!/bin/bash

[ -z "$BZ_DB_HOST" ] && echo "Missing Docker Environment, check docker-compose.yml" && exit -1
cd /var/www/html
apachectl start
while :
do
  echo "Waiting for database to be available..."
  nc -z $BZ_DB_HOST $BZ_DB_PORT
  [ $? -eq 0 ] && break
  sleep 2
done
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
s/%%BZ_ADMIN_EMAIL%%/'${BZ_ADMIN_EMAIL//@/\\@}'/;
s/%%BZ_ADMIN_PASSWORD%%/'${BZ_ADMIN_PASSWORD//@/\\@//$/\\$}'/;
s/%%BZ_ADMIN_REALNAME%%/'${BZ_ADMIN_REALNAME//@/\\@//$/\\$}'/;
s/%%BZ_DB_HOST%%/'$BZ_DB_HOST'/;
s/%%BZ_DB_PORT%%/$BZ_DB_PORT/;
s/%%BZ_DB_NAME%%/'$BZ_DB_NAME'/;
s/%%BZ_DB_USER%%/'$BZ_DB_USER'/;
s/%%BZ_DB_PASS%%/'${BZ_DB_PASS//@/\\@//$/\\$}'/;
s@%%BZ_URLBASE%%@'${BZ_URLBASE//@/\\@}'@;
" /root/docker/checksetup_answers.txt
perl checksetup.pl /root/docker/checksetup_answers.txt
echo "Checksetup completed."

LOGIN_USER="Admin user: $BZ_ADMIN_EMAIL"
LOGIN_PASS="Admin password: $BZ_ADMIN_PASSWORD"
cat - <<EOF
#########################################
##                                     ##
##  Your Bugzilla installation should  ##
##         now be reachable at:        ##
##                                     ##
EOF
printf "##%*s%*s##\n" $(( (${#BZ_URLBASE} + 37) / 2)) $BZ_URLBASE $(( 37 - ((${#BZ_URLBASE} + 37) / 2)  )) " "
cat - <<EOF
##                                     ##
EOF
printf "##%*s%*s##\n" $(( (${#LOGIN_USER} + 37) / 2)) "$LOGIN_USER" $(( 37 - ((${#LOGIN_USER} + 37) / 2)  )) " "
printf "##%*s%*s##\n" $(( (${#LOGIN_PASS} + 37) / 2)) "$LOGIN_PASS" $(( 37 - ((${#LOGIN_PASS} + 37) / 2)  )) " "
cat - <<EOF
##                                     ##
##   user/password only valid if you   ##
##    haven't already changed them.    ##
##                                     ##
#########################################
EOF
# don't exit docker
while [ 1 ]; do sleep 1000; done
