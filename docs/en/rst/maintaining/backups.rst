.. _backups:

Making Backups
##############

   Here are some sample commands you could use to backup
   your database, depending on what database system you're
   using. You may have to modify these commands for your
   particular setup.

   MySQL:
       mysqldump --opt -u bugs -p bugs > bugs.sql
   PostgreSQL:
       pg_dump --no-privileges --no-owner -h localhost -U bugs
       > bugs.sql

