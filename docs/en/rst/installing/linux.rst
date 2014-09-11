.. _linux:

Linux
#####

Many Linux distributions include Bugzilla and its dependencies in their
package management systems. If you have root access, installing Bugzilla on
any Linux system could be as simple as finding the Bugzilla package in the
package management application and installing it. There may be a small bit
of additional configuration required. If you are installing the machine from
scratch, :ref:`quick-start` may be the best instructions for you.

XXX What's our current position on Debian/Ubuntu packages of Bugzilla?

Install Packages
================

Use your distribution's package manager to install Perl, your preferred
database engine (MySQL if in doubt), and a webserver (Apache if in doubt).

XXX Package lists for specific distros

.. _install-perl:

Perl
====

Test which version of Perl you have installed with:
::

    $ perl -v

Bugzilla requires at least Perl |min-perl-ver|.

.. _install-bzfiles:

Bugzilla
========

The best way to get Bugzilla is to check it out from git:

:command:`git clone https://git.mozilla.org/bugzilla/bugzilla`

If that's not possible, you can
`download a tarball of Bugzilla <http://www.bugzilla.org/download/>`_.

Place Bugzilla in a suitable directory, accessible by the default web server
user (probably ``apache`` or ``www-data``).
Good locations are either directly in the web server's document directory
(often :file:`/var/www/html`) or in :file:`/usr/local`, either with a
symbolic link to the web server's document directory or an alias in the web
server's configuration.

.. warning:: The default Bugzilla distribution is NOT designed to be placed
   in a :file:`cgi-bin` directory. This
   includes any directory which is configured using the
   ``ScriptAlias`` directive of Apache.

Once all the files are in a web accessible directory, make that
directory writable by your web server's user. This is a temporary step
until you run the :file:`checksetup.pl` script, which locks down your
installation.

.. _install-perlmodules:

Perl Modules
============

Bugzilla requires a number of Perl modules. You can install these globally
using your system's package manager, or install Bugzilla-only copies. At
times, Bugzilla may require a version of a Perl module newer than the one
your distribution packages, in which case you will need to install a
Bugzilla-only copy of the newer version.

At this point, you need to :file:`su` to root. You should remain as root
until the end of the install.

XXX Is this true, if they are installing modules locally?

Install all missing modules locally like this:

:command:`./install-module.pl --all`

Or, you can pass an individual module name:

:command:`./install-module.pl <modulename>`

To check you indeed have new enough versions of all the required modules, run:

:command:`./checksetup.pl --check-modules`

You can run this command as many times as necessary.

.. note:: If you are using a package-based distribution, and attempting to
   install the Perl modules from CPAN (e.g. by using
   :file:`install-module.pl`), you may need to install the "development"
   packages for MySQL and GD before attempting to install the related Perl
   modules. The names of these packages will vary depending on the specific
   distribution you are using, but are often called
   :file:`<packagename>-devel`.

.. _config-database:

Web Server
==========

We have instructions for configuring Apache and IIS, although we strongly
recommend using Apache. However, pretty much any web server that is capable of
running CGI scripts will work.

.. toctree::
   :maxdepth: 1

   apache
   iis

XXX Don't need IIS in the Linux docs.

You can run :command:`testserver.pl http://bugzilla-url/` from the command
line to check if your web server is correctly configured.

XXX Does this work before doing any localconfig stuff?

Database Engine
===============

Bugzilla supports MySQL, PostgreSQL, Oracle and SQLite as database servers.
You only require one of these systems to make use of Bugzilla. MySQL is
most commonly used. SQLite is good for trial installations as it requires no
setup. Configure your server according to the instructions below.

.. toctree::
   :maxdepth: 1

   mysql
   postgresql
   oracle
   sqlite

.. _config-webserver:

.. _localconfig:

localconfig
===========

You should now run :file:`checksetup.pl` again, this time
without the ``--check-modules`` switch.

:command:`./checksetup.pl`

:file:`checksetup.pl` will write out a file called :file:`localconfig`.
This file contains the default settings for a number of
Bugzilla parameters, the most important of which are the group your web
server runs as, and information on how to connect to your database.

Load this file in your editor. The only two values you
need to change are ``$db_driver`` and ``$db_pass``,
respectively the type of the database and the password for
the user you will create for your database. Pick a strong
password (for simplicity, it should not contain single quote
characters) and put it here. ``$db_driver`` can be either ``mysql``,
``Pg``, ``Oracle`` or ``Sqlite`` (case-sensitive).

.. note:: In Oracle, ``$db_name`` should actually be
   the SID name of your database (e.g. "XE" if you are using Oracle XE).

Set the value of ``$webservergroup`` to the group your web server runs as.
The default is ``apache`` (correct for Red Hat/Fedora). On Debian and Ubuntu,
Apache uses the ``www-data`` group.

The other options in the :file:`localconfig` file are documented by their
accompanying comments. If you have a non-standard database setup, you may
need to change one or more of the other ``$db_*`` parameters.

checksetup.pl
=============

Next, run :file:`checksetup.pl` an additional. It reconfirms
that all the modules are present, and notices the altered
localconfig file, which it assumes you have edited to your
satisfaction. It compiles the UI templates,
connects to the database using the ``bugs``
user you created and the password you defined, and creates the
``bugs`` database and the tables therein.

After that, it asks for details of an administrator account. Bugzilla
can have multiple administrators - you can create more later - but
it needs one to start off with.
Enter the email address of an administrator, his or her full name,
and a suitable Bugzilla password.

:file:`checksetup.pl` will then finish. You may rerun
:file:`checksetup.pl` at any time if you wish.

.. _install-config-bugzilla:

Bugzilla
========

Your Bugzilla should now be working. Access
:file:`http://<your-bugzilla-server>/` -
you should see the Bugzilla front page.

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

== Gentoo ==
Gentoo pulls in all dependencies and, if you don't have the vhosts USE flag enabled, installs Bugzilla to /var/www/localhost/bugzilla when you issue:

<code># emerge -av bugzilla</code>

You will then have to configure and install your database according to your needs:

For a first time MySQL install:

<code># mysql_install_db</code>

Else:

<code># mysql -u root -p<br />
mysql>CREATE DATABASE databasename;<br />
mysql>GRANT <privs> ON databasename.* to 'bugzillauser'@'hostname' identified by 'pa$$w0rd';</code>
 
== Fedora ==

'''Please be aware of this:''' https://bugzilla.mozilla.org/show_bug.cgi?id=415605
(Please remove this link once determined the RPM has been repaired)

Bugzilla and its dependencies are in the Fedora yum repository. To install Bugzilla and all its Perl dependencies, simply do (as root)

<code>$ yum install bugzilla</code>

You also need to install the database engine and web server, for example MySQL and httpd:

<code>$ yum install httpd mysql-server</code>

The Fedora packages automatically do the httpd configuration, so there is no need to worry about that. 

To configure MySQL, you need to add the bugs user and bugs database to MySQL. You can do this with the normal MySQL tools - either use the command line, the mysqladmin tool, or the mysql-administrator GUI tool. You can also use a web-based control panel like PHPMyADMIN. Make sure the "bugs" user has write permissions ot the "bugs" database.

The next step is to configure <code>/etc/bugzilla/localconfig</code> with the right database information:

<pre>
# The name of the database
$db_name = 'bugs';

# Who we connect to the database as.
$db_user = 'bugs';

# Enter your database password here. It's normally advisable to specify
# a password for your bugzilla database user.
# If you use apostrophe (') or a backslash (\) in your password, you'll
# need to escape it by preceding it with a '\' character. (\') or (\)
# (Far simpler just not to use those characters.)
$db_pass = 'PASSWORD';
</pre>

Fedora stores the Bugzilla files in <code>/usr/share/bugzilla</code>. Change into that directory and run the <code>checksetup.pl</code> script. If any problems are encountered here, you can refer to the Bugzilla user guide.

Finally, start mysqld and httpd and browse to http://localhost/bugzilla
