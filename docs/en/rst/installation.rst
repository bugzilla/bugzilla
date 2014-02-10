.. highlight:: console

.. _installing-bugzilla:

===================
Installing Bugzilla
===================

.. _installation:

Installation
############

.. note:: If you just want to *use* Bugzilla,
   you do not need to install it. None of this chapter is relevant to
   you. Ask your Bugzilla administrator for the URL to access it from
   your web browser.

The Bugzilla server software is usually installed on Linux or
Solaris.
If you are installing on another OS, check :ref:`os-specific`
before you start your installation to see if there are any special
instructions.

This guide assumes that you have administrative access to the
Bugzilla machine. It not possible to
install and run Bugzilla itself without administrative access except
in the very unlikely event that every single prerequisite is
already installed.

.. warning:: The installation process may make your machine insecure for
   short periods of time. Make sure there is a firewall between you
   and the Internet.

You are strongly recommended to make a backup of your system
before installing Bugzilla (and at regular intervals thereafter :-).

In outline, the installation proceeds as follows:

#. :ref:`Install Perl <install-perl>`
   (|min-perl-ver| or above)

#. :ref:`Install a Database Engine <install-database>`

#. :ref:`Install a Webserver <install-webserver>`

#. :ref:`Install Bugzilla <install-bzfiles>`

#. :ref:`Install Perl modules <install-perlmodules>`

#. :ref:`Install a Mail Transfer Agent <install-MTA>`
   (Sendmail 8.7 or above, or an MTA that is Sendmail-compatible with at least this version)

#. Configure all of the above.

.. _install-perl:

Perl
====

Installed Version Test:
::

    $ perl -v

Any machine that doesn't have Perl on it is a sad machine indeed.
If you don't have it and your OS doesn't provide official packages,
visit `<http://www.perl.org>`_.
Although Bugzilla runs with Perl |min-perl-ver|,
it's a good idea to be using the latest stable version.

.. _install-database:

Database Engine
===============

Bugzilla supports MySQL, PostgreSQL and Oracle as database servers.
You only require one of these systems to make use of Bugzilla.

.. _install-mysql:

MySQL
-----

Installed Version Test:
::

    $ mysql -V

If you don't have it and your OS doesn't provide official packages,
visit `<http://www.mysql.com>`_. You need MySQL version
5.0.15 or higher.

.. note:: Many of the binary
   versions of MySQL store their data files in :file:`/var`.
   On some Unix systems, this is part of a smaller root partition,
   and may not have room for your bug database. To change the data
   directory, you have to build MySQL from source yourself, and
   set it as an option to :file:`configure`.

If you install from something other than a packaging/installation
system, such as .rpm (RPM Package Manager), .deb (Debian Package), .exe
(Windows Executable), or .msi (Windows Installer), make sure the MySQL
server is started when the machine boots.

.. _install-pg:

PostgreSQL
----------

Installed Version Test:
::

    $ psql -V

If you don't have it and your OS doesn't provide official packages,
visit `<http://www.postgresql.org/>`_. You need PostgreSQL
version 8.03.0000 or higher.

If you install from something other than a packaging/installation
system, such as .rpm (RPM Package Manager), .deb (Debian Package), .exe
(Windows Executable), or .msi (Windows Installer), make sure the
PostgreSQL server is started when the machine boots.

.. _install-oracle:

Oracle
------

Installed Version Test:

.. code-block:: sql

    SELECT * FROM v$version

(you first have to log in into your DB)

If you don't have it and your OS doesn't provide official packages,
visit `<http://www.oracle.com/>`_. You need Oracle
version 10.02.0 or higher.

If you install from something other than a packaging/installation
system, such as .rpm (RPM Package Manager), .deb (Debian Package), .exe
(Windows Executable), or .msi (Windows Installer), make sure the
Oracle server is started when the machine boots.

.. _install-webserver:

Web Server
==========

Installed Version Test: view the default welcome page at
`http://<your-machine>/` .

You have freedom of choice here, pretty much any web server that
is capable of running CGI
scripts will work.
However, we strongly recommend using the Apache web server
(either 1.3.x or 2.x), and the installation instructions usually assume
you are using it. If you have got Bugzilla working using another web server,
please share your experiences with us by filing a bug in
`Bugzilla Documentation <http://bugzilla.mozilla.org/enter_bug.cgi?product=Bugzilla;component=Documentation>`_.

If you don't have Apache and your OS doesn't provide official packages,
visit `<http://httpd.apache.org/>`_.

.. _install-bzfiles:

Bugzilla
========

`Download a Bugzilla tarball <http://www.bugzilla.org/download/>`_
(or `check it out from Bzr <https://wiki.mozilla.org/Bugzilla:Bzr>`_)
and place it in a suitable directory, accessible by the default web server user
(probably ``apache`` or ``www``).
Good locations are either directly in the web server's document directories or
in :file:`/usr/local` with a symbolic link to the web server's
document directories or an alias in the web server's configuration.

.. warning:: The default Bugzilla distribution is NOT designed to be placed
   in a :file:`cgi-bin` directory. This
   includes any directory which is configured using the
   ``ScriptAlias`` directive of Apache.

Once all the files are in a web accessible directory, make that
directory writable by your web server's user. This is a temporary step
until you run the
:file:`checksetup.pl`
script, which locks down your installation.

.. _install-perlmodules:

Perl Modules
============

Bugzilla's installation process is based
on a script called :file:`checksetup.pl`.
The first thing it checks is whether you have appropriate
versions of all the required
Perl modules. The aim of this section is to pass this check.
When it passes, proceed to :ref:`configuration`.

At this point, you need to :file:`su` to root. You should
remain as root until the end of the install. To check you have the
required modules, run:

::

    # ./checksetup.pl --check-modules

:file:`checksetup.pl` will print out a list of the
required and optional Perl modules, together with the versions
(if any) installed on your machine.
The list of required modules is reasonably long; however, you
may already have several of them installed.

The preferred way to install missing Perl modules is to use the package
manager provided by your operating system (e.g ``rpm``, ``apt-get`` or
``yum`` on Linux distros, or ``ppm`` on Windows
if using ActivePerl, see :ref:`win32-perl-modules`).
If some Perl modules are still missing or are too old, then we recommend
using the :file:`install-module.pl` script (doesn't work
with ActivePerl on Windows). For instance, on Unix,
you invoke :file:`install-module.pl` as follows:

::

    # perl install-module.pl <modulename>

.. note:: Many people complain that Perl modules will not install for
   them. Most times, the error messages complain that they are missing a
   file in
   ``@INC``.
   Virtually every time, this error is due to permissions being set too
   restrictively for you to compile Perl modules or not having the
   necessary Perl development libraries installed on your system.
   Consult your local UNIX systems administrator for help solving these
   permissions issues; if you
   *are*
   the local UNIX sysadmin, please consult the newsgroup/mailing list
   for further assistance or hire someone to help you out.

.. note:: If you are using a package-based system, and attempting to install the
   Perl modules from CPAN, you may need to install the "development" packages for
   MySQL and GD before attempting to install the related Perl modules. The names of
   these packages will vary depending on the specific distribution you are using,
   but are often called :file:`<packagename>-devel`.

If for some reason you really need to install the Perl modules manually, see
:ref:`install-perlmodules-manual`.

.. _install-MTA:

Mail Transfer Agent (MTA)
=========================

Bugzilla is dependent on the availability of an e-mail system for its
user authentication and for other tasks.

.. note:: This is not entirely true.  It is possible to completely disable
   email sending, or to have Bugzilla store email messages in a
   file instead of sending them.  However, this is mainly intended
   for testing, as disabling or diverting email on a production
   machine would mean that users could miss important events (such
   as bug changes or the creation of new accounts).
   For more information, see the ``mail_delivery_method`` parameter
   in :ref:`parameters`.

On Linux, any Sendmail-compatible MTA (Mail Transfer Agent) will
suffice.  Sendmail, Postfix, qmail and Exim are examples of common
MTAs. Sendmail is the original Unix MTA, but the others are easier to
configure, and therefore many people replace Sendmail with Postfix or
Exim. They are drop-in replacements, so Bugzilla will not
distinguish between them.

If you are using Sendmail, version 8.7 or higher is required.
If you are using a Sendmail-compatible MTA, it must be congruent with
at least version 8.7 of Sendmail.

Consult the manual for the specific MTA you choose for detailed
installation instructions. Each of these programs will have their own
configuration files where you must configure certain parameters to
ensure that the mail is delivered properly. They are implemented
as services, and you should ensure that the MTA is in the auto-start
list of services for the machine.

If a simple mail sent with the command-line 'mail' program
succeeds, then Bugzilla should also be fine.

.. _using-mod_perl-with-bugzilla:

Installing Bugzilla on mod_perl
===============================

It is now possible to run the Bugzilla software under ``mod_perl`` on
Apache. ``mod_perl`` has some additional requirements to that of running
Bugzilla under ``mod_cgi`` (the standard and previous way).

Bugzilla requires ``mod_perl`` to be installed, which can be
obtained from `<http://perl.apache.org>`_ - Bugzilla requires
version 1.999022 (AKA 2.0.0-RC5) to be installed.

.. _configuration:

Configuration
#############

.. warning:: Poorly-configured MySQL and Bugzilla installations have
   given attackers full access to systems in the past. Please take the
   security parts of these guidelines seriously, even for Bugzilla
   machines hidden away behind your firewall. Be certain to
   read :ref:`security` for some important security tips.

.. _localconfig:

localconfig
===========

You should now run :file:`checksetup.pl` again, this time
without the ``--check-modules`` switch.

::

    # ./checksetup.pl

This time, :file:`checksetup.pl` should tell you that all
the correct modules are installed and will display a message about, and
write out a  file called, :file:`localconfig`. This file
contains the default settings for a number of Bugzilla parameters.

Load this file in your editor. The only two values you
*need* to change are $db_driver and $db_pass,
respectively the type of the database and the password for
the user you will create for your database. Pick a strong
password (for simplicity, it should not contain single quote
characters) and put it here. $db_driver can be either 'mysql',
'Pg', 'Oracle' or 'Sqlite'.

.. note:: In Oracle, ``$db_name`` should actually be
   the SID name of your database (e.g. "XE" if you are using Oracle XE).

You may need to change the value of
*webservergroup* if your web server does not
run in the "apache" group.  On Debian, for example, Apache runs in
the "www-data" group.  If you are going to run Bugzilla on a
machine where you do not have root access (such as on a shared web
hosting account), you will need to leave
*webservergroup* empty, ignoring the warnings
that :file:`checksetup.pl` will subsequently display
every time it is run.

.. warning:: If you are using suexec, you should use your own primary group
   for *webservergroup* rather than leaving it
   empty, and see the additional directions in the suexec section :ref:`suexec`.

The other options in the :file:`localconfig` file
are documented by their accompanying comments. If you have a slightly
non-standard database setup, you may wish to change one or more of
the other "$db_*" parameters.

.. _database-engine:

Database Server
===============

This section deals with configuring your database server for use
with Bugzilla. Currently, MySQL (:ref:`mysql`),
PostgreSQL (:ref:`postgresql`), Oracle (:ref:`oracle`)
and SQLite (:ref:`sqlite`) are available.

.. _database-schema:

Bugzilla Database Schema
------------------------

The Bugzilla database schema is available at
`Ravenbrook <http://www.ravenbrook.com/project/p4dti/tool/cgi/bugzilla-schema/>`_.
This very valuable tool can generate a written description of
the Bugzilla database schema for any version of Bugzilla. It
can also generate a diff between two versions to help someone
see what has changed.

.. _mysql:

MySQL
-----

.. warning:: MySQL's default configuration is insecure.
   We highly recommend to run :file:`mysql_secure_installation`
   on Linux or the MySQL installer on Windows, and follow the instructions.
   Important points to note are:

#. Be sure that the root account has a secure password set.
#. Do not create an anonymous account, and if it exists, say "yes"
   to remove it.
#. If your web server and MySQL server are on the same machine,
   you should disable the network access.

.. _mysql-max-allowed-packet:

Allow large attachments and many comments
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

By default, MySQL will only allow you to insert things
into the database that are smaller than 1MB. Attachments
may be larger than this. Also, Bugzilla combines all comments
on a single bug into one field for full-text searching, and the
combination of all comments on a single bug could in some cases
be larger than 1MB.

To change MySQL's default, you need to edit your MySQL
configuration file, which is usually :file:`/etc/my.cnf`
on Linux. We recommend that you allow at least 4MB packets by
adding the "max_allowed_packet" parameter to your MySQL
configuration in the "\[mysqld]" section, like this:

::

    [mysqld]
    # Allow packets up to 4MB
    max_allowed_packet=4M

Allow small words in full-text indexes
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

By default, words must be at least four characters in length
in order to be indexed by MySQL's full-text indexes. This causes
a lot of Bugzilla specific words to be missed, including "cc",
"ftp" and "uri".

MySQL can be configured to index those words by setting the
ft_min_word_len param to the minimum size of the words to index.
This can be done by modifying the :file:`/etc/my.cnf`
according to the example below:

::

    [mysqld]
    # Allow small words in full-text indexes
    ft_min_word_len=2

Rebuilding the indexes can be done based on documentation found at
`<http://www.mysql.com/doc/en/Fulltext_Fine-tuning.html>`_.

.. _install-setupdatabase-adduser:

Add a user to MySQL
~~~~~~~~~~~~~~~~~~~

You need to add a new MySQL user for Bugzilla to use.
(It's not safe to have Bugzilla use the MySQL root account.)
The following instructions assume the defaults in
:file:`localconfig`; if you changed those,
you need to modify the SQL command appropriately. You will
need the $db_pass password you
set in :file:`localconfig` in
:ref:`localconfig`.

We use an SQL :command:`GRANT` command to create
a ``bugs`` user. This also restricts the
``bugs`` user to operations within a database
called ``bugs``, and only allows the account
to connect from ``localhost``. Modify it to
reflect your setup if you will be connecting from another
machine or as a different user.

Run the :file:`mysql` command-line client and enter:

.. code-block:: sql

    GRANT SELECT, INSERT,
    UPDATE, DELETE, INDEX, ALTER, CREATE, LOCK TABLES,
    CREATE TEMPORARY TABLES, DROP, REFERENCES ON bugs.*
    TO bugs@localhost IDENTIFIED BY '$db_pass';

    FLUSH PRIVILEGES;

Permit attachments table to grow beyond 4GB
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

By default, MySQL will limit the size of a table to 4GB.
This limit is present even if the underlying filesystem
has no such limit.  To set a higher limit, follow these
instructions.

After you have completed the rest of the installation (or at least the
database setup parts), you should run the :file:`MySQL`
command-line client and enter the following, replacing ``$bugs_db``
with your Bugzilla database name (*bugs* by default):

.. code-block:: sql

    USE $bugs_db;
    
    ALTER TABLE attachments AVG_ROW_LENGTH=1000000, MAX_ROWS=20000;

The above command will change the limit to 20GB. Mysql will have
to make a temporary copy of your entire table to do this. Ideally,
you should do this when your attachments table is still small.

.. note:: This does not affect Big Files, attachments that are stored directly
   on disk instead of in the database.

.. _postgresql:

PostgreSQL
----------

Add a User to PostgreSQL
~~~~~~~~~~~~~~~~~~~~~~~~

You need to add a new user to PostgreSQL for the Bugzilla
application to use when accessing the database. The following instructions
assume the defaults in :file:`localconfig`; if you
changed those, you need to modify the commands appropriately. You will
need the $db_pass password you
set in :file:`localconfig` in
:ref:`localconfig`.

On most systems, to create the user in PostgreSQL, you will need to
login as the root user, and then

::

    # su - postgres

As the postgres user, you then need to create a new user:

::

    $ createuser -U postgres -dRSP bugs

When asked for a password, provide the password which will be set as
$db_pass in :file:`localconfig`.
The created user will not be a superuser (-S) and will not be able to create
new users (-R). He will only have the ability to create databases (-d).

Configure PostgreSQL
~~~~~~~~~~~~~~~~~~~~

Now, you will need to edit :file:`pg_hba.conf` which is
usually located in :file:`/var/lib/pgsql/data/`. In this file,
you will need to add a new line to it as follows:

``host   all    bugs   127.0.0.1    255.255.255.255  md5``

This means that for TCP/IP (host) connections, allow connections from
'127.0.0.1' to 'all' databases on this server from the 'bugs' user, and use
password authentication (md5) for that user.

Now, you will need to restart PostgreSQL, but you will need to fully
stop and start the server rather than just restarting due to the possibility
of a change to :file:`postgresql.conf`. After the server has
restarted, you will need to edit :file:`localconfig`, finding
the ``$db_driver`` variable and setting it to
``Pg`` and changing the password in ``$db_pass``
to the one you picked previously, while setting up the account.

.. _oracle:

Oracle
------

Create a New Tablespace
~~~~~~~~~~~~~~~~~~~~~~~

You can use the existing tablespace or create a new one for Bugzilla.
To create a new tablespace, run the following command:

.. code-block:: sql

    CREATE TABLESPACE bugs
    DATAFILE '*$path_to_datafile*' SIZE 500M
    AUTOEXTEND ON NEXT 30M MAXSIZE UNLIMITED

Here, the name of the tablespace is 'bugs', but you can
choose another name. *$path_to_datafile* is
the path to the file containing your database, for instance
:file:`/u01/oradata/bugzilla.dbf`.
The initial size of the database file is set in this example to 500 Mb,
with an increment of 30 Mb everytime we reach the size limit of the file.

Add a User to Oracle
~~~~~~~~~~~~~~~~~~~~

The user name and password must match what you set in
:file:`localconfig` (``$db_user``
and ``$db_pass``, respectively). Here, we assume that
the user name is 'bugs' and the tablespace name is the same
as above.

.. code-block:: sql

    CREATE USER bugs
    IDENTIFIED BY "$db_pass"
    DEFAULT TABLESPACE bugs
    TEMPORARY TABLESPACE TEMP
    PROFILE DEFAULT;
    -- GRANT/REVOKE ROLE PRIVILEGES
    GRANT CONNECT TO bugs;
    GRANT RESOURCE TO bugs;
    -- GRANT/REVOKE SYSTEM PRIVILEGES
    GRANT UNLIMITED TABLESPACE TO bugs;
    GRANT EXECUTE ON CTXSYS.CTX_DDL TO bugs;

Configure the Web Server
~~~~~~~~~~~~~~~~~~~~~~~~

If you use Apache, append these lines to :file:`httpd.conf`
to set ORACLE_HOME and LD_LIBRARY_PATH. For instance:

.. code-block:: apache

    SetEnv ORACLE_HOME /u01/app/oracle/product/10.2.0/
    SetEnv LD_LIBRARY_PATH /u01/app/oracle/product/10.2.0/lib/

When this is done, restart your web server.

.. _sqlite:

SQLite
------

.. warning:: Due to SQLite's `concurrency
   limitations <http://sqlite.org/faq.html#q5>`_ we recommend SQLite only for small and development
   Bugzilla installations.

No special configuration is required to run Bugzilla on SQLite.
The database will be stored in :file:`data/db/$db_name`,
where ``$db_name`` is the database name defined
in :file:`localconfig`.

checksetup.pl
=============

Next, rerun :file:`checksetup.pl`. It reconfirms
that all the modules are present, and notices the altered
localconfig file, which it assumes you have edited to your
satisfaction. It compiles the UI templates,
connects to the database using the 'bugs'
user you created and the password you defined, and creates the
'bugs' database and the tables therein.

After that, it asks for details of an administrator account. Bugzilla
can have multiple administrators - you can create more later - but
it needs one to start off with.
Enter the email address of an administrator, his or her full name,
and a suitable Bugzilla password.

:file:`checksetup.pl` will then finish. You may rerun
:file:`checksetup.pl` at any time if you wish.

.. _http:

Web server
==========

Configure your web server according to the instructions in the
appropriate section. (If it makes a difference in your choice,
the Bugzilla Team recommends Apache.) To check whether your web server
is correctly configured, try to access :file:`testagent.cgi`
from your web server. If "OK" is displayed, then your configuration
is successful. Regardless of which web server
you are using, however, ensure that sensitive information is
not remotely available by properly applying the access controls in
:ref:`security-webserver-access`. You can run
:file:`testserver.pl` to check if your web server serves
Bugzilla files as expected.

.. _http-apache:

Bugzilla using Apache
---------------------

You have two options for running Bugzilla under Apache -
:ref:`mod_cgi <http-apache-mod_cgi>` (the default) and
:ref:`mod_perl <http-apache-mod_perl>` (new in Bugzilla
2.23)

.. _http-apache-mod_cgi:

Apache *httpd* with mod_cgi
~~~~~~~~~~~~~~~~~~~~~~~~~~~

To configure your Apache web server to work with Bugzilla while using
mod_cgi, do the following:

#. Load :file:`httpd.conf` in your editor.
   In Fedora and Red Hat Linux, this file is found in
   :file:`/etc/httpd/conf`.

#. Apache uses ``<Directory>``
   directives to permit fine-grained permission setting. Add the
   following lines to a directive that applies to the location
   of your Bugzilla installation. (If such a section does not
   exist, you'll want to add one.) In this example, Bugzilla has
   been installed at :file:`/var/www/html/bugzilla`.

.. code-block:: apache

       <Directory /var/www/html/bugzilla>
       AddHandler cgi-script .cgi
       Options +ExecCGI
       DirectoryIndex index.cgi index.html
       AllowOverride Limit FileInfo Indexes Options
       </Directory>

These instructions: allow apache to run .cgi files found
within the bugzilla directory; instructs the server to look
for a file called :file:`index.cgi` or, if not
found, :file:`index.html` if someone
only types the directory name into the browser; and allows
Bugzilla's :file:`.htaccess` files to override
some global permissions.

.. note:: It is possible to make these changes globally, or to the
   directive controlling Bugzilla's parent directory (e.g.
   ``<Directory /var/www/html/>``).
   Such changes would also apply to the Bugzilla directory...
   but they would also apply to many other places where they
   may or may not be appropriate. In most cases, including
   this one, it is better to be as restrictive as possible
   when granting extra access.

.. note:: On Windows, you may have to also add the
   ``ScriptInterpreterSource Registry-Strict``
   line, see :ref:`Windows specific notes <win32-http>`.

#. :file:`checksetup.pl` can set tighter permissions
   on Bugzilla's files and directories if it knows what group the
   web server runs as. Find the ``Group``
   line in :file:`httpd.conf`, place the value found
   there in the *$webservergroup* variable
   in :file:`localconfig`, then rerun :file:`checksetup.pl`.

#. Optional: If Bugzilla does not actually reside in the webspace
   directory, but instead has been symbolically linked there, you
   will need to add the following to the
   ``Options`` line of the Bugzilla
   ``<Directory>`` directive
   (the same one as in the step above):

.. code-block:: apache

       +FollowSymLinks

Without this directive, Apache will not follow symbolic links
to places outside its own directory structure, and you will be
unable to run Bugzilla.

.. _http-apache-mod_perl:

Apache *httpd* with mod_perl
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Some configuration is required to make Bugzilla work with Apache
and mod_perl

#. Load :file:`httpd.conf` in your editor.
   In Fedora and Red Hat Linux, this file is found in :file:`/etc/httpd/conf`.

#. Add the following information to your httpd.conf file, substituting
   where appropriate with your own local paths.

   .. note:: This should be used instead of the <Directory> block
      shown above. This should also be above any other ``mod_perl``
      directives within the :file:`httpd.conf` and must be specified
      in the order as below.

   .. warning:: You should also ensure that you have disabled ``KeepAlive``
      support in your Apache install when utilizing Bugzilla under mod_perl

.. code-block:: apache

       PerlSwitches -w -T
       PerlConfigRequire /var/www/html/bugzilla/mod_perl.pl

#. :file:`checksetup.pl` can set tighter permissions
   on Bugzilla's files and directories if it knows what group the
   web server runs as. Find the ``Group``
   line in :file:`httpd.conf`, place the value found
   there in the *$webservergroup* variable
   in :file:`localconfig`, then rerun :file:`checksetup.pl`.

On restarting Apache, Bugzilla should now be running within the
mod_perl environment. Please ensure you have run checksetup.pl to set
permissions before you restart Apache.

.. note:: Please bear the following points in mind when looking at using
   Bugzilla under mod_perl:

   - mod_perl support in Bugzilla can take up a HUGE amount of RAM. You could be
     looking at 30MB per httpd child, easily. Basically, you just need a lot of RAM.
     The more RAM you can get, the better. mod_perl is basically trading RAM for
     speed. At least 2GB total system RAM is recommended for running Bugzilla under
     mod_perl.
   - Under mod_perl, you have to restart Apache if you make any manual change to
     any Bugzilla file. You can't just reload--you have to actually
     *restart* the server (as in make sure it stops and starts
     again). You *can* change localconfig and the params file
     manually, if you want, because those are re-read every time you load a page.
   - You must run in Apache's Prefork MPM (this is the default). The Worker MPM
     may not work--we haven't tested Bugzilla's mod_perl support under threads.
     (And, in fact, we're fairly sure it *won't* work.)
   - Bugzilla generally expects to be the only mod_perl application running on
     your entire server. It may or may not work if there are other applications also
     running under mod_perl. It does try its best to play nice with other mod_perl
     applications, but it still may have conflicts.
   - It is recommended that you have one Bugzilla instance running under mod_perl
     on your server. Bugzilla has not been tested with more than one instance running.

.. _http-iis:

Microsoft *Internet Information Services*
-----------------------------------------

If you are running Bugzilla on Windows and choose to use
Microsoft's *Internet Information Services*
or *Personal Web Server* you will need
to perform a number of other configuration steps as explained below.
You may also want to refer to the following Microsoft Knowledge
Base articles:
`245225 - HOW TO: Configure and Test a PERL Script with IIS 4.0,
5.0, and 5.1 <http://support.microsoft.com/default.aspx?scid=kb;en-us;245225>`_
(for *Internet Information Services*) and
`231998 - HOW TO: FP2000: How to Use Perl with Microsoft Personal Web
Server on Windows 95/98 <http://support.microsoft.com/default.aspx?scid=kb;en-us;231998>`_
(for *Personal Web Server*).

You will need to create a virtual directory for the Bugzilla
install.  Put the Bugzilla files in a directory that is named
something *other* than what you want your
end-users accessing.  That is, if you want your users to access
your Bugzilla installation through
``http://<yourdomainname>/Bugzilla``, then do
*not* put your Bugzilla files in a directory
named ``Bugzilla``.  Instead, place them in a different
location, and then use the IIS Administration tool to create a
Virtual Directory named "Bugzilla" that acts as an alias for the
actual location of the files.  When creating that virtual directory,
make sure you add the ``Execute (such as ISAPI applications or
CGI)`` access permission.

You will also need to tell IIS how to handle Bugzilla's
.cgi files. Using the IIS Administration tool again, open up
the properties for the new virtual directory and select the
Configuration option to access the Script Mappings. Create an
entry mapping .cgi to:

::

    <full path to perl.exe >\perl.exe -x<full path to Bugzilla> -wT "%s" %s

For example:

::

    c:\perl\bin\perl.exe -xc:\bugzilla -wT "%s" %s

.. note:: The ActiveState install may have already created an entry for
   .pl files that is limited to ``GET,HEAD,POST``. If
   so, this mapping should be *removed* as
   Bugzilla's .pl files are not designed to be run via a web server.

IIS will also need to know that the index.cgi should be treated
as a default document.  On the Documents tab page of the virtual
directory properties, you need to add index.cgi as a default
document type.  If you  wish, you may remove the other default
document types for this particular virtual directory, since Bugzilla
doesn't use any of them.

Also, and this can't be stressed enough, make sure that files
such as :file:`localconfig` and your
:file:`data` directory are
secured as described in :ref:`security-webserver-access`.

.. _install-config-bugzilla:

Bugzilla
========

Your Bugzilla should now be working. Access
:file:`http://<your-bugzilla-server>/` -
you should see the Bugzilla
front page. If not, consult the Troubleshooting section,
:ref:`troubleshooting`.

.. note:: The URL above may be incorrect if you installed Bugzilla into a
   subdirectory or used a symbolic link from your web site root to
   the Bugzilla directory.

Log in with the administrator account you defined in the last
:file:`checksetup.pl` run. You should go through
the Parameters page and see if there are any you wish to change.
They key parameters are documented in :ref:`parameters`;
you should certainly alter
:command:`maintainer` and :command:`urlbase`;
you may also want to alter
:command:`cookiepath` or :command:`requirelogin`.

Bugzilla has several optional features which require extra
configuration. You can read about those in
:ref:`extraconfig`.

.. _extraconfig:

Optional Additional Configuration
#################################

Bugzilla has a number of optional features. This section describes how
to configure or enable them.

Bug Graphs
==========

If you have installed the necessary Perl modules you
can start collecting statistics for the nifty Bugzilla
graphs.

::

    # crontab -e

This should bring up the crontab file in your editor.
Add a cron entry like this to run
:file:`collectstats.pl`
daily at 5 after midnight:

.. code-block:: none

    5 0 * * * cd <your-bugzilla-directory> && ./collectstats.pl

After two days have passed you'll be able to view bug graphs from
the Reports page.

.. note:: Windows does not have 'cron', but it does have the Task
   Scheduler, which performs the same duties. There are also
   third-party tools that can be used to implement cron, such as
   `nncron <http://www.nncron.ru/>`_.

.. _installation-whining-cron:

The Whining Cron
================

What good are
bugs if they're not annoying? To help make them more so you
can set up Bugzilla's automatic whining system to complain at engineers
which leave their bugs in the CONFIRMED state without triaging them.

This can be done by adding the following command as a daily
crontab entry, in the same manner as explained above for bug
graphs. This example runs it at 12.55am.

.. code-block:: none

    55 0 * * * cd <your-bugzilla-directory> && ./whineatnews.pl

.. note:: Windows does not have 'cron', but it does have the Task
   Scheduler, which performs the same duties. There are also
   third-party tools that can be used to implement cron, such as
   `nncron <http://www.nncron.ru/>`_.

.. _installation-whining:

Whining
=======

As of Bugzilla 2.20, users can configure Bugzilla to regularly annoy
them at regular intervals, by having Bugzilla execute saved searches
at certain times and emailing the results to the user.  This is known
as "Whining".  The process of configuring Whining is described
in :ref:`whining`, but for it to work a Perl script must be
executed at regular intervals.

This can be done by adding the following command as a daily
crontab entry, in the same manner as explained above for bug
graphs. This example runs it every 15 minutes.

.. code-block:: none

    */15 * * * * cd <your-bugzilla-directory> && ./whine.pl

.. note:: Whines can be executed as often as every 15 minutes, so if you specify
   longer intervals between executions of whine.pl, some users may not
   be whined at as often as they would expect.  Depending on the person,
   this can either be a very Good Thing or a very Bad Thing.

.. note:: Windows does not have 'cron', but it does have the Task
   Scheduler, which performs the same duties. There are also
   third-party tools that can be used to implement cron, such as
   `nncron <http://www.nncron.ru/>`_.

.. _apache-addtype:

Serving Alternate Formats with the right MIME type
==================================================

Some Bugzilla pages have alternate formats, other than just plain
HTML. In particular, a few Bugzilla pages can
output their contents as either XUL (a special
Mozilla format, that looks like a program GUI)
or RDF (a type of structured XML
that can be read by various programs).

In order for your users to see these pages correctly, Apache must
send them with the right MIME type. To do this,
add the following lines to your Apache configuration, either in the
``<VirtualHost>`` section for your
Bugzilla, or in the ``<Directory>``
section for your Bugzilla:

.. code-block:: apache

    AddType application/vnd.mozilla.xul+xml .xul
    AddType application/rdf+xml .rdf

.. _multiple-bz-dbs:

Multiple Bugzilla databases with a single installation
######################################################

The previous instructions referred to a standard installation, with
one unique Bugzilla database. However, you may want to host several
distinct installations, without having several copies of the code. This is
possible by using the PROJECT environment variable. When accessed,
Bugzilla checks for the existence of this variable, and if present, uses
its value to check for an alternative configuration file named
:file:`localconfig.<PROJECT>` in the same location as
the default one (:file:`localconfig`). It also checks for
customized templates in a directory named
:file:`<PROJECT>` in the same location as the
default one (:file:`template/<langcode>`). By default
this is :file:`template/en/default` so PROJECT's templates
would be located at :file:`template/en/PROJECT`.

To set up an alternate installation, just export PROJECT=foo before
running :command:`checksetup.pl` for the first time. It will
result in a file called :file:`localconfig.foo` instead of
:file:`localconfig`. Edit this file as described above, with
reference to a new database, and re-run :command:`checksetup.pl`
to populate it. That's all.

Now you have to configure the web server to pass this environment
variable when accessed via an alternate URL, such as virtual host for
instance. The following is an example of how you could do it in Apache,
other Webservers may differ.

.. code-block:: apache

    <VirtualHost 212.85.153.228:80>
    ServerName foo.bar.baz
    SetEnv PROJECT foo
    Alias /bugzilla /var/www/bugzilla
    </VirtualHost>

Don't forget to also export this variable before accessing Bugzilla
by other means, such as cron tasks for instance.

.. _os-specific:

OS-Specific Installation Notes
##############################

Many aspects of the Bugzilla installation can be affected by the
operating system you choose to install it on. Sometimes it can be made
easier and others more difficult. This section will attempt to help you
understand both the difficulties of running on specific operating systems
and the utilities available to make it easier.

If you have anything to add or notes for an operating system not covered,
please file a bug in `Bugzilla Documentation <http://bugzilla.mozilla.org/enter_bug.cgi?product=Bugzilla;component=Documentation>`_.

.. _os-win32:

Microsoft Windows
=================

Making Bugzilla work on Windows is more difficult than making it
work on Unix.  For that reason, we still recommend doing so on a Unix
based system such as GNU/Linux.  That said, if you do want to get
Bugzilla running on Windows, you will need to make the following
adjustments. A detailed step-by-step
`installation guide for Windows <https://wiki.mozilla.org/Bugzilla:Win32Install>`_ is also available
if you need more help with your installation.

.. _win32-perl:

Win32 Perl
----------

Perl for Windows can be obtained from
`ActiveState <http://www.activestate.com/>`_.
You should be able to find a compiled binary at `<http://aspn.activestate.com/ASPN/Downloads/ActivePerl/>`_.
The following instructions assume that you are using version
|min-perl-ver| of ActiveState.

.. note:: These instructions are for 32-bit versions of Windows. If you are
   using a 64-bit version of Windows, you will need to install 32-bit
   Perl in order to install the 32-bit modules as described below.

.. _win32-perl-modules:

Perl Modules on Win32
---------------------

Bugzilla on Windows requires the same perl modules found in
:ref:`install-perlmodules`. The main difference is that
windows uses PPM instead
of CPAN. ActiveState provides a GUI to manage Perl modules. We highly
recommend that you use it. If you prefer to use ppm from the
command-line, type:

::

    C:\perl> ppm install <module name>

If you are using Perl |min-perl-ver|, the best source for the Windows PPM modules
needed for Bugzilla is probably the theory58S website, which you can add
to your list of repositories as follows:

::

    ppm repo add theory58S http://cpan.uwinnipeg.ca/PPMPackages/10xx/

If you are using Perl 5.12 or newer, you no longer need to add
this repository. All modules you need are already available from
the ActiveState repository.

.. note:: The PPM repository stores modules in 'packages' that may have
   a slightly different name than the module.  If retrieving these
   modules from there, you will need to pay attention to the information
   provided when you run :command:`checksetup.pl` as it will
   tell you what package you'll need to install.

.. note:: If you are behind a corporate firewall, you will need to let the
   ActiveState PPM utility know how to get through it to access
   the repositories by setting the HTTP_proxy system environmental
   variable. For more information on setting that variable, see
   the ActiveState documentation.

.. _win32-http:

Serving the web pages
---------------------

As is the case on Unix based systems, any web server should
be able to handle Bugzilla; however, the Bugzilla Team still
recommends Apache whenever asked. No matter what web server
you choose, be sure to pay attention to the security notes
in :ref:`security-webserver-access`. More
information on configuring specific web servers can be found
in :ref:`http`.

.. note:: The web server looks at :file:`/usr/bin/perl` to
   call Perl. If you are using Apache on windows, you can set the
   `ScriptInterpreterSource <http://httpd.apache.org/docs-2.0/mod/core.html#scriptinterpretersource>`_
   directive in your Apache config file to make it look at the
   right place: insert the line

   ::
       ScriptInterpreterSource Registry-Strict

   into your :file:`httpd.conf` file, and create the key

   ::
       HKEY_CLASSES_ROOT\\.cgi\\Shell\\ExecCGI\\Command

   with ``C:\\Perl\\bin\\perl.exe -T`` as value (adapt to your
   path if needed) in the registry. When this is done, restart Apache.

.. _win32-email:

Sending Email
-------------

To enable Bugzilla to send email on Windows, the server running the
Bugzilla code must be able to connect to, or act as, an SMTP server.

.. _os-macosx:

*Mac OS X*
==========

Making Bugzilla work on Mac OS X requires the following
adjustments.

.. _macosx-sendmail:

Sendmail
--------

In Mac OS X 10.3 and later,
`Postfix <http://www.postfix.org/>`_
is used as the built-in email server.  Postfix provides an executable
that mimics sendmail enough to fool Bugzilla, as long as Bugzilla can
find it. Bugzilla is able to find the fake sendmail executable without
any assistance.

.. _macosx-libraries:

Libraries & Perl Modules on Mac OS X
------------------------------------

Apple does not include the GD library with Mac OS X. Bugzilla
needs this for bug graphs.

You can use MacPorts (`<http://www.macports.org/>`_)
or Fink (`<http://sourceforge.net/projects/fink/>`_), both
of which are similar in nature to the CPAN installer, but install
common unix programs.

Follow the instructions for setting up MacPorts or Fink.
Once you have one installed, you'll want to use it to install the
:file:`gd2` package.

Fink will prompt you for a number of dependencies, type 'y' and hit
enter to install all of the dependencies and then watch it work. You will
then be able to use CPAN to
install the GD Perl module.

.. note:: To prevent creating conflicts with the software that Apple
   installs by default, Fink creates its own directory tree at :file:`/sw`
   where it installs most of
   the software that it installs. This means your libraries and headers
   will be at :file:`/sw/lib` and :file:`/sw/include` instead
   of :file:`/usr/lib` and :file:`/usr/include`. When the
   Perl module config script asks where your :file:`libgd`
   is, be sure to tell it :file:`/sw/lib`.

Also available via MacPorts and Fink is
:file:`expat`. After installing the expat package, you
will be able to install XML::Parser using CPAN. If you use fink, there
is one caveat. Unlike recent versions of
the GD module, XML::Parser doesn't prompt for the location of the
required libraries. When using CPAN, you will need to use the following
command sequence:

::

    # perl -MCPAN -e'look XML::Parser'
    # perl Makefile.PL EXPATLIBPATH=/sw/lib EXPATINCPATH=/sw/include
    # make; make test; make install
    # exit

The :command:`look` command will download the module and spawn
a new shell with the extracted files as the current working directory.

You should watch the output from these :command:`make` commands,
especially ``make test`` as errors may prevent
XML::Parser from functioning correctly with Bugzilla.

The :command:`exit` command will return you to your original shell.

.. _os-linux:

Linux Distributions
===================

Many Linux distributions include Bugzilla and its
dependencies in their native package management systems.
Installing Bugzilla with root access on any Linux system
should be as simple as finding the Bugzilla package in the
package management application and installing it using the
normal command syntax. Several distributions also perform
the proper web server configuration automatically on installation.

Please consult the documentation of your Linux
distribution for instructions on how to install packages,
or for specific instructions on installing Bugzilla with
native package management tools. There is also a
`Bugzilla Wiki Page <http://wiki.mozilla.org/Bugzilla:Linux_Distro_Installation>`_ for distro-specific installation
notes.

.. _nonroot:

UNIX (non-root) Installation Notes
##################################

Introduction
============

If you are running a \*NIX OS as non-root, either due
to lack of access (web hosts, for example) or for security
reasons, this will detail how to install Bugzilla on such
a setup. It is recommended that you read through the
:ref:`installation`
first to get an idea on the installation steps required.
(These notes will reference to steps in that guide.)

MySQL
=====

You may have MySQL installed as root. If you're
setting up an account with a web host, a MySQL account
needs to be set up for you. From there, you can create
the bugs account, or use the account given to you.

.. warning:: You may have problems trying to set up :command:`GRANT`
   permissions to the database.
   If you're using a web host, chances are that you have a
   separate database which is already locked down (or one big
   database with limited/no access to the other areas), but you
   may want to ask your system administrator what the security
   settings are set to, and/or run the :command:`GRANT`
   command for you.
   Also, you will probably not be able to change the MySQL
   root user password (for obvious reasons), so skip that
   step.

Running MySQL as Non-Root
-------------------------

The Custom Configuration Method
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Create a file .my.cnf in your
home directory (using /home/foo in this example)
as follows....

::

    [mysqld]
    datadir=/home/foo/mymysql
    socket=/home/foo/mymysql/thesock
    port=8081
    [mysql]
    socket=/home/foo/mymysql/thesock
    port=8081
    [mysql.server]
    user=mysql
    basedir=/var/lib
    [safe_mysqld]
    err-log=/home/foo/mymysql/the.log
    pid-file=/home/foo/mymysql/the.pid

The Custom Built Method
~~~~~~~~~~~~~~~~~~~~~~~

You can install MySQL as a not-root, if you really need to.
Build it with PREFIX set to :file:`/home/foo/mysql`,
or use pre-installed executables, specifying that you want
to put all of the data files in :file:`/home/foo/mysql/data`.
If there is another MySQL server running on the system that you
do not own, use the -P option to specify a TCP port that is not
in use.

Starting the Server
~~~~~~~~~~~~~~~~~~~

After your mysqld program is built and any .my.cnf file is
in place, you must initialize the databases (ONCE).

::

    $ mysql_install_db

Then start the daemon with

::

    $ safe_mysql &

After you start mysqld the first time, you then connect to
it as "root" and :command:`GRANT` permissions to other
users. (Again, the MySQL root account has nothing to do with
the \*NIX root account.)

.. note:: You will need to start the daemons yourself. You can either
   ask your system administrator to add them to system startup files, or
   add a crontab entry that runs a script to check on these daemons
   and restart them if needed.

.. warning:: Do NOT run daemons or other services on a server without first
   consulting your system administrator! Daemons use up system resources
   and running one may be in violation of your terms of service for any
   machine on which you are a user!

Perl
====

On the extremely rare chance that you don't have Perl on
the machine, you will have to build the sources
yourself. The following commands should get your system
installed with your own personal version of Perl:

::

    $ wget http://perl.org/CPAN/src/stable.tar.gz
    $ tar zvxf stable.tar.gz
    $ cd perl-|min-perl-ver|
    $ sh Configure -de -Dprefix=/home/foo/perl
    $ make && make test && make install

Once you have Perl installed into a directory (probably
in :file:`~/perl/bin`), you will need to
install the Perl Modules, described below.

.. _install-perlmodules-nonroot:

Perl Modules
============

Installing the Perl modules as a non-root user is accomplished by
running the :file:`install-module.pl`
script. For more details on this script, see the
`install-module.pl documentation <../html/api/install-module.html>`_.

HTTP Server
===========

Ideally, this also needs to be installed as root and
run under a special web server account. As long as
the web server will allow the running of \*.cgi files outside of a
cgi-bin, and a way of denying web access to certain files (such as a
.htaccess file), you should be good in this department.

Running Apache as Non-Root
--------------------------

You can run Apache as a non-root user, but the port will need
to be set to one above 1024. If you type :command:`httpd -V`,
you will get a list of the variables that your system copy of httpd
uses. One of those, namely HTTPD_ROOT, tells you where that
installation looks for its config information.

From there, you can copy the config files to your own home
directory to start editing. When you edit those and then use the -d
option to override the HTTPD_ROOT compiled into the web server, you
get control of your own customized web server.

.. note:: You will need to start the daemons yourself. You can either
   ask your system administrator to add them to system startup files, or
   add a crontab entry that runs a script to check on these daemons
   and restart them if needed.

.. warning:: Do NOT run daemons or other services on a server without first
   consulting your system administrator! Daemons use up system resources
   and running one may be in violation of your terms of service for any
   machine on which you are a user!

Bugzilla
========

When you run :command:`./checksetup.pl` to create
the :file:`localconfig` file, it will list the Perl
modules it finds. If one is missing, go back and double-check the
module installation from :ref:`install-perlmodules-nonroot`,
then delete the :file:`localconfig` file and try again.

.. warning:: One option in :file:`localconfig` you
   might have problems with is the web server group. If you can't
   successfully browse to the :file:`index.cgi` (like
   a Forbidden error), you may have to relax your permissions,
   and blank out the web server group. Of course, this may pose
   as a security risk. Having a properly jailed shell and/or
   limited access to shell accounts may lessen the security risk,
   but use at your own risk.

.. _suexec:

suexec or shared hosting
------------------------

If you are running on a system that uses suexec (most shared
hosting environments do this), you will need to set the
*webservergroup* value in :file:`localconfig`
to match *your* primary group, rather than the one
the web server runs under.  You will need to run the following
shell commands after running :command:`./checksetup.pl`,
every time you run it (or modify :file:`checksetup.pl`
to do them for you via the system() command).

::

    for i in docs graphs images js skins; do find $i -type d -exec chmod o+rx {} \\; ; done
    for i in jpg gif css js png html rdf xul; do find . -name \\*.$i -exec chmod o+r {} \\; ; done
    find . -name .htaccess -exec chmod o+r {} \\;
    chmod o+x . data data/webdot

Pay particular attention to the number of semicolons and dots.
They are all important.  A future version of Bugzilla will
hopefully be able to do this for you out of the box.

.. _upgrade:

Upgrading to New Releases
#########################

Upgrading to new Bugzilla releases is very simple. There is
a script named :file:`checksetup.pl` included with
Bugzilla that will automatically do all of the database migration
for you.

The following sections explain how to upgrade from one
version of Bugzilla to another. Whether you are upgrading
from one bug-fix version to another (such as 4.2 to 4.2.1)
or from one major version to another (such as from 4.0 to 4.2),
the instructions are always the same.

.. note:: Any examples in the following sections are written as though the
   user were updating to version 4.2.1, but the procedures are the
   same no matter what version you're updating to. Also, in the
   examples, the user's Bugzilla installation is found
   at :file:`/var/www/html/bugzilla`. If that is not the
   same as the location of your Bugzilla installation, simply
   substitute the proper paths where appropriate.

.. _upgrade-before:

Before You Upgrade
==================

Before you start your upgrade, there are a few important
steps to take:

#. Read the `Release
   Notes <http://www.bugzilla.org/releases/>`_ of the version you're upgrading to,
   particularly the "Notes for Upgraders" section.

#. View the Sanity Check (:ref:`sanitycheck`) page
   on your installation before upgrading. Attempt to fix all warnings
   that the page produces before you go any further, or you may
   experience problems  during your upgrade.

#. Shut down your Bugzilla installation by putting some HTML or
   text in the shutdownhtml parameter
   (see :ref:`parameters`).

#. Make a backup of the Bugzilla database.
   *THIS IS VERY IMPORTANT*. If
   anything goes wrong during the upgrade, your installation
   can be corrupted beyond recovery. Having a backup keeps you safe.

   .. warning:: Upgrading is a one-way process. You cannot "downgrade" an
      upgraded Bugzilla. If you wish to revert to the old Bugzilla
      version for any reason, you will have to restore your database
      from this backup.

   Here are some sample commands you could use to backup
   your database, depending on what database system you're
   using. You may have to modify these commands for your
   particular setup.

   MySQL:
       mysqldump --opt -u bugs -p bugs > bugs.sql
   PostgreSQL:
       pg_dump --no-privileges --no-owner -h localhost -U bugs
       > bugs.sql

.. _upgrade-files:

Getting The New Bugzilla
========================

There are three ways to get the new version of Bugzilla.
We'll list them here briefly and then explain them
more later.

Bzr (:ref:`upgrade-bzr`)
    If you have :command:`bzr` installed on your machine
    and you have Internet access, this is the easiest way to
    upgrade, particularly if you have made modifications
    to the code or templates of Bugzilla.

Download the tarball (:ref:`upgrade-tarball`)
    This is a very simple way to upgrade, and good if you
    haven't made many (or any) modifications to the code or
    templates of your Bugzilla.

Patches (:ref:`upgrade-patches`)
    If you have made modifications to your Bugzilla, and
    you don't have Internet access or you don't want to use
    bzr, then this is the best way to upgrade.
    You can only do minor upgrades (such as 4.2 to 4.2.1 or
    4.2.1 to 4.2.2) with patches.

.. _upgrade-modified:

If you have modified your Bugzilla
----------------------------------

If you have modified the code or templates of your Bugzilla,
then upgrading requires a bit more thought and effort.
A discussion of the various methods of updating compared with
degree and methods of local customization can be found in
:ref:`template-method`.

The larger the jump you are trying to make, the more difficult it
is going to be to upgrade if you have made local customizations.
Upgrading from 4.2 to 4.2.1 should be fairly painless even if
you are heavily customized, but going from 2.18 to 4.2 is going
to mean a fair bit of work re-writing your local changes to use
the new files, logic, templates, etc. If you have done no local
changes at all, however, then upgrading should be approximately
the same amount of work regardless of how long it has been since
your version was released.

.. _upgrade-bzr:

Upgrading using Bzr
-------------------

This requires that you have bzr installed (most Unix machines do),
and requires that you are able to access
`bzr.mozilla.org <http://bzr.mozilla.org/bugzilla/>`_,
which may not be an option if you don't have Internet access.

The following shows the sequence of commands needed to update a
Bugzilla installation via Bzr, and a typical series of results.
These commands assume that you already have Bugzilla installed
using Bzr.

.. warning:: If your installation is still using CVS, you must first convert
   it to Bzr. A very detailed step by step documentation can be
   found on `wiki.mozilla.org <https://wiki.mozilla.org/Bugzilla:Moving_From_CVS_To_Bazaar>`_.

::

    $ cd /var/www/html/bugzilla
    $ bzr switch 4.2
      (only run the previous command when not yet running 4.2)
    $ bzr up -r tag:bugzilla-4.2.1
    +N  extensions/MoreBugUrl/
    +N  extensions/MoreBugUrl/Config.pm
    +N  extensions/MoreBugUrl/Extension.pm
    ...
    M  Bugzilla/Attachment.pm
    M  Bugzilla/Attachment/PatchReader.pm
    M  Bugzilla/Bug.pm
    ...
    All changes applied successfully.

.. warning:: If a line in the output from :command:`bzr up` mentions
   a conflict, then that represents a file with local changes that
   Bzr was unable to properly merge. You need to resolve these
   conflicts manually before Bugzilla (or at least the portion using
   that file) will be usable.

.. _upgrade-tarball:

Upgrading using the tarball
---------------------------

If you are unable (or unwilling) to use Bzr, another option that's
always available is to obtain the latest tarball from the `Download Page <http://www.bugzilla.org/download/>`_ and
create a new Bugzilla installation from that.

This sequence of commands shows how to get the tarball from the
command-line; it is also possible to download it from the site
directly in a web browser. If you go that route, save the file
to the :file:`/var/www/html`
directory (or its equivalent, if you use something else) and
omit the first three lines of the example.

::

    $ cd /var/www/html
    $ wget http://ftp.mozilla.org/pub/mozilla.org/webtools/bugzilla-4.2.1.tar.gz
    ...
    $ tar xzvf bugzilla-4.2.1.tar.gz
    bugzilla-4.2.1/
    bugzilla-4.2.1/colchange.cgi
    ...
    $ cd bugzilla-4.2.1
    $ cp ../bugzilla/localconfig* .
    $ cp -r ../bugzilla/data .
    $ cd ..
    $ mv bugzilla bugzilla.old
    $ mv bugzilla-4.2.1 bugzilla

.. warning:: The :command:`cp` commands both end with periods which
   is a very important detail--it means that the destination
   directory is the current working directory.

.. warning:: If you have some extensions installed, you will have to copy them
   to the new bugzilla directory too. Extensions are located in :file:`bugzilla/extensions/`.
   Only copy those you
   installed, not those managed by the Bugzilla team.

This upgrade method will give you a clean install of Bugzilla.
That's fine if you don't have any local customizations that you
want to maintain. If you do have customizations, then you will
need to reapply them by hand to the appropriate files.

.. _upgrade-patches:

Upgrading using patches
-----------------------

A patch is a collection of all the bug fixes that have been made
since the last bug-fix release.

If you are doing a bug-fix upgrade—that is, one where only the
last number of the revision changes, such as from 4.2 to
4.2.1—then you have the option of obtaining and applying a
patch file from the `Download Page <http://www.bugzilla.org/download/>`_.

As above, this example starts with obtaining the file via the
command line. If you have already downloaded it, you can omit the
first two commands.

::

    $ cd /var/www/html/bugzilla
    $ wget http://ftp.mozilla.org/pub/mozilla.org/webtools/bugzilla-4.2-to-4.2.1.diff.gz
    ...
    $ gunzip bugzilla-4.2-to-4.2.1.diff.gz
    $ patch -p1 < bugzilla-4.2-to-4.2.1.diff
    patching file Bugzilla/Constants.pm
    patching file enter_bug.cgi
    ...

.. warning:: Be aware that upgrading from a patch file does not change the
   entries in your :file:`.bzr` directory.
   This could make it more difficult to upgrade using Bzr
   (:ref:`upgrade-bzr`) in the future.

.. _upgrade-completion:

Completing Your Upgrade
=======================

Now that you have the new Bugzilla code, there are a few final
steps to complete your upgrade.

#. If your new Bugzilla installation is in a different
   directory or on a different machine than your old Bugzilla
   installation, make sure that you have copied the
   :file:`data` directory and the
   :file:`localconfig` file from your old Bugzilla
   installation. (If you followed the tarball instructions
   above, this has already happened.)

#. If this is a major update, check that the configuration
   (:ref:`configuration`) for your new Bugzilla is
   up-to-date. Sometimes the configuration requirements change
   between major versions.

#. If you didn't do it as part of the above configuration step,
   now you need to run :command:`checksetup.pl`, which
   will do everything required to convert your existing database
   and settings for the new version:

   ::
   
       $ :command:`cd /var/www/html/bugzilla`
       $ :command:`./checksetup.pl`

   .. warning:: The period at the beginning of the
      command :command:`./checksetup.pl` is important and cannot
      be omitted.

   .. warning:: If this is a major upgrade (say, 3.6 to 4.2 or similar),
      running :command:`checksetup.pl` on a large
      installation (75,000 or more bugs) can take a long time,
      possibly several hours.

#. Clear any HTML or text that you put into the shutdownhtml
   parameter, to re-activate Bugzilla.

#. View the Sanity Check (:ref:`sanitycheck`) page in your
   upgraded Bugzilla.
   It is recommended that, if possible, you fix any problems
   you see, immediately. Failure to do this may mean that Bugzilla
   will not work correctly. Be aware that if the sanity check page
   contains more errors after an upgrade, it doesn't necessarily
   mean there are more errors in your database than there were
   before, as additional tests are added to the sanity check over
   time, and it is possible that those errors weren't being
   checked for in the old version.

.. _upgrade-notifications:

Automatic Notifications of New Releases
=======================================

Bugzilla 3.0 introduced the ability to automatically notify
administrators when new releases are available, based on the
``upgrade_notification`` parameter, see
:ref:`parameters`. Administrators will see these
notifications when they access the :file:`index.cgi`
page, i.e. generally when logging in. Bugzilla will check once per
day for new releases, unless the parameter is set to
``disabled``. If you are behind a proxy, you may have to set
the ``proxy_url`` parameter accordingly. If the proxy
requires authentication, use the
``http://user:pass@proxy_url/`` syntax.


