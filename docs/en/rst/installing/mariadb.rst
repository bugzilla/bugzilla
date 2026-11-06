.. _mariadb:

MariaDB
#######

The minimum required version is MariaDB 10.0.5.

It's possible to test which version of MariaDB you have installed with:

:command:`mariadb -e 'select version()'`

For MariaDB versions prior to 10.4.6, replace the :command:`mariadb` command 
with :command:`mysql` with the same arguments. 

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
on your machine, if it didn't come with it already. 

If you did install MariaDB manually rather than from a package, make sure the
server is started when the machine boots.

.. _mariadb-add-user:

Add a User
==========

You need to add a new MariaDB user for Bugzilla to use. Run the :file:`mariadb`
command-line client and enter:

::

    CREATE USER 'bugs'@'localhost' IDENTIFIED BY '$DB_PASS';

    GRANT SELECT, INSERT,
    UPDATE, DELETE, INDEX, ALTER, CREATE, LOCK TABLES,
    CREATE TEMPORARY TABLES, DROP, REFERENCES ON bugs.*
    TO 'bugs'@'localhost';

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
* Mac OS X: :file:`/etc/my.cnf`

Or :file:`mariadb.cnf` on Unix-like operating systems.

.. _mariadb-max-allowed-packet:

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

.. _mariadb-small-words:

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

.. _mariadb-attach-table-size:
