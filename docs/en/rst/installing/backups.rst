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

See the
`mysqldump documentation <http://dev.mysql.com/doc/mysql/en/mysqldump.html>`_
for more information on :file:`mysqldump`.

.. todo:: Mention max_allowed_packet? Convert this item to a bug on checkin.

PostgreSQL
----------

:command:`pg_dump --no-privileges --no-owner -h localhost -U $USERNAME > bugs.sql`

Bugzilla
========

The Bugzilla directory contains some data files and configuration files which
you would want to retain. A simple recursive copy will do the job here.

:command:`cp -rp $BUGZILLA_HOME /var/backups/bugzilla`

