#!/bin/bash

[ -z "$BZ_DB_HOST" ] && echo "Missing Docker Environment, check docker-compose.yml" && exit -1
export BZ_DB_SSL="${BZ_DB_SSL:-1}"
export BZ_DB_SSL_VERIFY="${BZ_DB_SSL_VERIFY:-0}"
export BZ_DB_SSL_CA_FILE="${BZ_DB_SSL_CA_FILE:-/etc/ssl/certs/ca-certificates.crt}"
if [[ ! "$BZ_DB_SSL" =~ ^[01]$ || ! "$BZ_DB_SSL_VERIFY" =~ ^[01]$ ]]; then
  echo "BZ_DB_SSL and BZ_DB_SSL_VERIFY must be 0 or 1" >&2
  exit 1
fi
if [[ "$BZ_DB_SSL" == 0 && "$BZ_DB_SSL_VERIFY" == 1 ]]; then
  echo "BZ_DB_SSL_VERIFY requires BZ_DB_SSL=1" >&2
  exit 1
fi
if [[ "$BZ_DB_SSL_VERIFY" == 1 && ! -r "$BZ_DB_SSL_CA_FILE" ]]; then
  echo "Database TLS CA file is not readable: $BZ_DB_SSL_CA_FILE" >&2
  exit 1
fi
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
perl /root/docker/setup_database.pl || exit $?
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
s/%%BZ_ALLOW_UNSAFE_UTF8_CONVERSION%%/${BZ_ALLOW_UNSAFE_UTF8_CONVERSION:-0}/;
" /root/docker/checksetup_answers.txt

# Answers are evaluated in a restricted Perl compartment, so serialize the
# values here instead of trying to read the environment from the answers file.
perl -MData::Dumper -pi -e '
  my %values = (
    BZ_DB_SSL => $ENV{BZ_DB_SSL},
    BZ_DB_SSL_VERIFY => $ENV{BZ_DB_SSL_VERIFY},
    BZ_DB_SSL_CA_FILE => ($ENV{BZ_DB_SSL} && $ENV{BZ_DB_SSL_VERIFY})
      ? $ENV{BZ_DB_SSL_CA_FILE} : "",
  );
  for my $key (keys %values) {
    my $value = Data::Dumper->new([$values{$key}])->Terse(1)->Indent(0)->Dump;
    s/%%\Q$key\E%%/$value/g;
  }
' /root/docker/checksetup_answers.txt

CHECKSETUP_LOG=$(mktemp)
perl checksetup.pl /root/docker/checksetup_answers.txt 2>&1 | tee "$CHECKSETUP_LOG"
CHECKSETUP_EXIT=${PIPESTATUS[0]}

if [ $CHECKSETUP_EXIT -ne 0 ]; then
  if grep -q "Re-run checksetup.pl in interactive mode" "$CHECKSETUP_LOG"; then
    cat - <<EOF

checksetup.pl stopped because a potentially destructive conversion requires
explicit approval in non-interactive mode.

To proceed with the UTF-8 conversion in Docker, re-run with:
  BZ_ALLOW_UNSAFE_UTF8_CONVERSION=1 docker compose up

Only use this if you understand the warning and have a database backup.
EOF
  fi
  exit $CHECKSETUP_EXIT
fi

rm -f "$CHECKSETUP_LOG"
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
