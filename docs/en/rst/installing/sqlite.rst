.. _install-sqlite:

SQLite
######

.. warning:: Due to SQLite's `concurrency
   limitations <http://sqlite.org/faq.html#q5>`_ we recommend SQLite only for
   small and development Bugzilla installations.

Once you have SQLite installed, no additional configuration is required to
run Bugzilla. Simply set $db_driver to "Sqlite" (case-sensitive) in
:file:`localconfig`, when you get to that point in the installation.

XXX This doesn't work - gives a timezone-related error on my box.

The database will be stored in :file:`data/db/$db_name`, where ``$db_name``
is the database name defined in :file:`localconfig`.
