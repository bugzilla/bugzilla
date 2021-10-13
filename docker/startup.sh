#!/bin/sh

cd /var/www/html
apachectl start
echo "Beginning checksetup..."
perl checksetup.pl --no-template docker/checksetup_answers.txt
echo "Checksetup completed."
while [ 1 ]; do sleep 1000; done
