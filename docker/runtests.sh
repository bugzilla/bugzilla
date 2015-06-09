#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

if [ -z "$TEST_SUITE" ]; then
    TEST_SUITE=sanity
fi

set -e

# Output to log file as well as STDOUT/STDERR
exec > >(tee /runtests.log) 2>&1

echo "== Retrieving Bugzilla code"
echo "Checking out $GITHUB_BASE_GIT $GITHUB_BASE_BRANCH ..."
mv $BUGZILLA_ROOT "${BUGZILLA_ROOT}.back"
git clone $GITHUB_BASE_GIT --single-branch --depth 1 --branch $GITHUB_BASE_BRANCH $BUGZILLA_ROOT
cd $BUGZILLA_ROOT
if [ "$GITHUB_BASE_REV" != "" ]; then
    echo "Switching to revision $GITHUB_BASE_REV ..."
    git checkout -q $GITHUB_BASE_REV
fi

echo -e "\n== Checking dependencies for changes"
/install_deps.sh

if [ "$TEST_SUITE" = "sanity" ]; then
    cd $BUGZILLA_ROOT
    /buildbot_step "Sanity" prove -f -v t/*.t
    exit $?
fi

if [ "$TEST_SUITE" = "docs" ]; then
    export JADE_PUB=/usr/share/sgml
    export LDP_HOME=/usr/share/sgml/docbook/dsssl-stylesheets-1.79/dtds/decls
    cd $BUGZILLA_ROOT/docs
    /buildbot_step "Documentation" perl makedocs.pl --with-pdf
    exit $?
fi

echo -e "\n== Cloning QA test suite"
cd $BUGZILLA_ROOT
echo "Cloning git repo $GITHUB_QA_GIT branch $GITHUB_BASE_BRANCH ..."
git clone $GITHUB_QA_GIT -b $GITHUB_BASE_BRANCH qa

echo -e "\n== Starting database"
/usr/bin/mysqld_safe &
sleep 3

echo -e "\n== Starting memcached"
/usr/bin/memcached -u memcached -d
sleep 3

echo -e "\n== Updating configuration"
mysql -u root mysql -e "CREATE DATABASE bugs_test CHARACTER SET = 'utf8';"
sed -e "s?%DB%?$BUGS_DB_DRIVER?g" --in-place qa/config/checksetup_answers.txt
sed -e "s?%DB_NAME%?bugs_test?g" --in-place qa/config/checksetup_answers.txt
sed -e "s?%USER%?$BUGZILLA_USER?g" --in-place qa/config/checksetup_answers.txt
echo "\$answer{'memcached_servers'} = 'localhost:11211';" >> qa/config/checksetup_answers.txt

if [ "$TEST_SUITE" == "checksetup" ]; then
    cd $BUGZILLA_ROOT/qa
    /buildbot_step "Checksetup" ./test_checksetup.pl config/config-checksetup-$BUGS_DB_DRIVER
    exit $?
fi

echo -e "\n== Running checksetup"
cd $BUGZILLA_ROOT
./checksetup.pl qa/config/checksetup_answers.txt
./checksetup.pl qa/config/checksetup_answers.txt

echo -e "\n== Generating bmo data"
perl /generate_bmo_data.pl

echo -e "\n== Generating test data"
cd $BUGZILLA_ROOT/qa/config
perl generate_test_data.pl

echo -e "\n== Starting web server"
sed -e "s?^#Perl?Perl?" --in-place /etc/httpd/conf.d/bugzilla.conf
/usr/sbin/httpd &
sleep 3

if [ "$TEST_SUITE" = "selenium" ]; then
    export DISPLAY=:0

    # Setup dbus for Firefox
    dbus-uuidgen > /var/lib/dbus/machine-id

    echo -e "\n== Starting virtual frame buffer and vnc server"
    Xvnc $DISPLAY -screen 0 1280x1024x16 -ac -SecurityTypes=None \
         -extension RANDR 2>&1 | tee /xvnc.log &
    sleep 5

    echo -e "\n== Starting Selenium server"
    java -jar /selenium-server.jar -log /selenium.log > /dev/null 2>&1 &
    sleep 5

    # Set NO_TESTS=1 if just want selenium services
    # but no tests actually executed.
    [ $NO_TESTS ] && exit 0

    cd $BUGZILLA_ROOT/qa/t
    /buildbot_step "Selenium" prove -f -v -I$BUGZILLA_ROOT/lib test_*.t
    exit $?
fi

if [ "$TEST_SUITE" = "webservices" ]; then
    cd $BUGZILLA_ROOT/qa/t
    /buildbot_step "Webservices" prove -f -v -I$BUGZILLA_ROOT/lib webservice_*.t
    exit $?
fi
