.. _moving:

Moving Bugzilla Between Machines
################################

Sometimes it's necessary to take a working installation of Bugzilla and move
it to new hardware. This page explains how to do that, assuming that you
have Bugzilla's webserver and database on the same machine, and you are moving
both of them.

You are advised to install the same version of Bugzilla on the new
machine as the old machine - any :ref:`upgrade <upgrading>` you also need to
do can then be done as a separate step. But if you do install a newer version,
things should still work.

1. Shut down your Bugzilla by loading the front page, going to
   :guilabel:`Administration` | :guilabel:`Parameters` | :guilabel:`General`
   and putting some text into the :guilabel:`shutdownhtml` parameter.

2. Make a backup of the bugs database. For a typical Bugzilla setup using
   MySQL, such a command might look like this:

   :command:`mysqldump -u<username> -p bugs > bugzilla-backup.sql`

   See the
   `mysqldump documentation <http://dev.mysql.com/doc/mysql/en/mysqldump.html>`_
   for more information on :file:`mysqldump`.

3. On your new machine, install Bugzilla using the instructions at
   :ref:`installing`. Look at the old machine if you need to know what values
   you used for configuring e.g. MySQL.

   XXX Need to say how far to go on the install

4. Copy the :file:`data` directory and the :file:`localconfig` file from the
   old Bugzilla installation to the new one.

5. If anything about your database configuration changed (location of the
   server, username, password, etc.) as part of the move, update the
   appropriate variables in :file:`localconfig`.

6. If the new URL to your new Bugzilla installation is different from the old
   one, update the :guilabel:`urlbase` parameter in :file:`data/params` using
   a text editor.

7. Copy the database backup file :file:`bugzilla-backup.sql` file from your
   old server to the new one.

8. Create an empty "bugs" database on the new server:

   :command:`mysql -u root -p -e "CREATE DATABASE bugs DEFAULT CHARACTER SET utf8;"`

9. Import your :file:`bugzilla-backup.sql` file into your new "bugs" database:

   :command:`mysql -u root -p bugs < bugzilla-backup.sql`

   If you get an error about "packet too large" or "mysql server has gone
   away", you need to adjust the :guilabel:`max_allowed_packet` setting in
   your :file:`my.cnf` file (usually :file:`/etc/my.cnf`) file to be larger
   than the largest attachment ever added to your Bugzilla.

   If there are *any* errors during this step, you have to drop the
   database, create it again using the step above, and do the import again.

10. Run :file:`checksetup.pl` to make sure all is OK.
    (Unless you are using a newer version of Bugzilla on your new server, this
    should not make any changes.)

    :command:`./checksetup.pl`

11. Activate your new Bugzilla by loading the front page, going to
    :guilabel:`Administration` | :guilabel:`Parameters` | :guilabel:`General`
    and removing the text from the :guilabel:`shutdownhtml` parameter.
