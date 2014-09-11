.. _install-mysql:

MySQL
#####

Test which version of MySQL you have installed with:

:command:`mysql -V`

You need MySQL version 5.0.15 or higher.

If you install MySQL manually rather than from a package, make sure the
server is started when the machine boots.

.. _secure-mysql:

Secure MySQL
============

On non-Windows platforms, run

:command:`mysql_secure_installation`

and follow its advice.

Add a user
==========

You need to add a new MySQL user for Bugzilla to use. Run the :file:`mysql`
command-line client and enter:

::

    GRANT SELECT, INSERT,
    UPDATE, DELETE, INDEX, ALTER, CREATE, LOCK TABLES,
    CREATE TEMPORARY TABLES, DROP, REFERENCES ON bugs.*
    TO bugs@localhost IDENTIFIED BY '$db_pass';

    FLUSH PRIVILEGES;

The above permits an account called ``bugs``
to connect from the local machine, ``localhost``. Modify the command to
reflect your setup if you will be connecting from another
machine or as a different user.

Make a note of the password you set.

.. _mysql-max-allowed-packet:

Allow large attachments and many comments
=========================================

To change MySQL's configuration, you need to edit your MySQL
configuration file, which is usually :file:`/etc/my.cnf`
on Linux.

By default, MySQL will only allow you to insert things
into the database that are smaller than 1MB. Bugzilla attachments
may be larger than this. Also, Bugzilla combines all comments
on a single bug into one field for full-text searching, and the
combination of all comments on a single bug could in some cases
be larger than 1MB.

We recommend that you allow at least 16MB packets by
adding the ``max_allowed_packet`` parameter to your MySQL
configuration in the ``[mysqld]`` section, like this:

::

    [mysqld]
    # Allow packets up to 16MB
    max_allowed_packet=16M

Allow small words in full-text indexes
======================================

By default, words must be at least four characters in length
in order to be indexed by MySQL's full-text indexes. This causes
a lot of Bugzilla-specific words to be missed, including "cc",
"ftp" and "uri".

MySQL can be configured to index those words by setting the
``ft_min_word_len`` param to the minimum size of the words to index.

::

    [mysqld]
    # Allow small words in full-text indexes
    ft_min_word_len=2

.. _install-setupdatabase-adduser:

Permit attachments table to grow beyond 4GB
===========================================

This is optional configuration for Bugzillas which are expected to become
very large, and needs to be done after Bugzilla is fully installed.

By default, MySQL will limit the size of a table to 4GB.
This limit is present even if the underlying filesystem
has no such limit.  To set a higher limit, run the :file:`mysql`
command-line client and enter the following, replacing ``$bugs_db``
with your Bugzilla database name (which is ``bugs`` by default):

.. code-block:: sql

    USE $bugs_db;
    
    ALTER TABLE attachments AVG_ROW_LENGTH=1000000, MAX_ROWS=20000;

The above command will change the limit to 20GB. MySQL will have
to make a temporary copy of your entire table to do this, so ideally
you should do this when your attachments table is still small.

.. note:: If you have set the setting in Bugzilla which allows large
   attachments to be stored on disk, the above change does not affect that.
