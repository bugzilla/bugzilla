#!/bin/bash
# You can manually run this script if you start getting MySQL errors about
# a table being corrupt.  This will preserve the data in your tables.

# scripts location (where does this config file live?)
SCRIPTS_DIR="$(dirname "$(readlink /proc/$$/fd/255)")"
source $SCRIPTS_DIR/settings.cfg

echo "repair table BugHistory;" | mysql -h$DB_HOST $DB_NAME -u$DB_USER -p$DB_PASS
echo "repair table Bugs;" | mysql -h$DB_HOST $DB_NAME -u$DB_USER -p$DB_PASS
echo "repair table Details;" | mysql -h$DB_HOST $DB_NAME -u$DB_USER -p$DB_PASS
echo "repair table Stats;" | mysql -h$DB_HOST $DB_NAME -u$DB_USER -p$DB_PASS
