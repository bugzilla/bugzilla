.. _mysql:

MariaDB
#######

It is strongly advised to use MariaDB which is a drop-in replacement for
MySQL and is fully compatible with Bugzilla. 

If MySQL is used, be aware that the minimum required version is MySQL 5.0.15.

All commands in this document work regardless of whether MariaDB or MySQL are used.

It's possible to test which version of MariaDB you have installed with:

:command:`mysql -V`

Installing
==========

Windows
-------

Download the MariaDB 32-bit or 64-bit MSI installer from the
`MariaDB website <https://mariadb.org/download/?t=mariadb&os=windows>`_ (~66 MB).

MariaDB has a standard Windows installer. It's ok to select a the
default install options. The rest of this documentation assumes assume you
have installed MariaDB into :file:`C:\\mysql`. Adjust paths appropriately if not.

Linux/Mac OS X
--------------

The package install instructions given previously should have installed MariaDB
on your machine, if it didn't come with it already. Run:

:command:`mysql_secure_installation`

and follow its advice.

If you did install MariaDB manually rather than from a package, make sure the
server is started when the machine boots.

Create the Database
===================

You need to create a database for Bugzilla to use. Run the :file:`mysql`
command-line client and enter:

::
    CREATE DATABASE IF NOT EXISTS bugs CHARACTER SET = 'utf8';

The above command makes sure a database like that doesn't exist already.

.. _mysql-add-user:

Add a User
==========

You need to add a new MariaDB user for Bugzilla to use. Run the :file:`mysql`
command-line client and enter:

::

    GRANT SELECT, INSERT,
    UPDATE, DELETE, INDEX, ALTER, CREATE, LOCK TABLES,
    CREATE TEMPORARY TABLES, DROP, REFERENCES ON bugs.*
    TO bugs@localhost IDENTIFIED BY '$DB_PASS';

    FLUSH PRIVILEGES;

You need to replace ``$DB_PASS`` with a strong password you have chosen.
Write that password down somewhere.

The above command permits an account called ``bugs``
to connect from the local machine, ``localhost``. Modify the command to
reflect your setup if you will be connecting from another
machine or as a different user.

Change Configuration
====================

To change MariaDB's configuration, you need to edit your MariaDB
configuration file, which is:

* Red Hat/Fedora: :file:`/etc/my.cnf`
* Debian/Ubuntu: :file:`/etc/mysql/my.cnf`
* Windows: :file:`C:\\mysql\\bin\\my.ini`
* Mac OS X: :file:`/etc/my/cnf`

.. _mysql-max-allowed-packet:

Allow Large Attachments and Many Comments
-----------------------------------------

By default on some systems, MariaDB will only allow you to insert things
into the database that are smaller than 1MB.

Bugzilla attachments
may be larger than this. Also, Bugzilla combines all comments
on a single bug into one field for full-text searching, and the
combination of all comments on a single bug could in some cases
be larger than 1MB.

We recommend that you allow at least 16MB packets by
adding or altering the ``max_allowed_packet`` parameter in your MariaDB
configuration in the ``[mysqld]`` section, so that the number is at least
16M, like this (note that it's ``M``, not ``MB``):

::

    [mysqld]
    # Allow packets up to 16M
    max_allowed_packet=16M

.. _mysql-small-words:

Allow Small Words in Full-Text Indexes
--------------------------------------

By default, words must be at least four characters in length
in order to be indexed by MariaDB's full-text indexes. This causes
a lot of Bugzilla-specific words to be missed, including "cc",
"ftp" and "uri".

MariaDB can be configured to index those words by setting the
``ft_min_word_len`` param to the minimum size of the words to index.

::

    [mysqld]
    # Allow small words in full-text indexes
    ft_min_word_len=2

.. _mysql-attach-table-size:

Permit Attachments Table to Grow Beyond 4GB
===========================================

This is optional configuration for Bugzillas which are expected to become
very large, and needs to be done after Bugzilla is fully installed.

By default, MariaDB will limit the size of a table to 4GB.
This limit is present even if the underlying filesystem
has no such limit.  To set a higher limit, run the :file:`mysql`
command-line client and enter the following, replacing ``$bugs_db``
with your Bugzilla database name (which is ``bugs`` by default):

.. code-block:: sql
   :force:

    USE $bugs_db;
    
    ALTER TABLE attachments AVG_ROW_LENGTH=1000000, MAX_ROWS=20000;

The above command will change the limit to 20GB. MariaDB will have
to make a temporary copy of your entire table to do this, so ideally
you should do this when your attachments table is still small.

.. note:: If you have set the setting in Bugzilla which allows large
   attachments to be stored on disk, the above change does not affect that.
