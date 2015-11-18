#!/bin/bash

cd $BUGZILLA_ROOT

# Start and initialize database
/usr/bin/mysqld_safe &
sleep 5
mysql -u root mysql -e "GRANT ALL PRIVILEGES ON *.* TO bugs@localhost IDENTIFIED BY 'bugs'; FLUSH PRIVILEGES;"
mysql -u root mysql -e "CREATE DATABASE bugs CHARACTER SET = 'utf8';"

# Setup default Bugzilla database
perl checksetup.pl /files/checksetup_answers.txt
perl checksetup.pl /files/checksetup_answers.txt
perl /scripts/generate_bmo_data.pl

# Shutdown database
mysqladmin -u root shutdown
