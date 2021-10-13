#!/bin/sh

cd /var/www/html
apachectl start
echo "Beginning checksetup..."
perl checksetup.pl docker/checksetup_answers.txt
echo "Checksetup completed."
# don't exit docker
while [ 1 ]; do sleep 1000; done
