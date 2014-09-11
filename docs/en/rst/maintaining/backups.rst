.. _backups:

Backups
#######

Database
========

Here are some sample commands you could use to backup
your database, depending on what database system you're
using. You may have to modify these commands for your
particular setup. Replace the $VARIABLEs with appropriate values for your
setup.

MySQL
-----

:command:`mysqldump --opt -u $USERNAME -p $DATABASENAME > backup.sql`

PostgreSQL
----------

:command:`pg_dump --no-privileges --no-owner -h localhost -U $USERNAME > bugs.sql`

Bugzilla
========

It's also a good idea to back up the Bugzilla directory itself, as there are
some data files and configuration files stored there which you would want to
retain. A simple recursive copy will do the job here.

:command:`cp -rp $BUGZILLA_HOME /var/backups/bugzilla`

