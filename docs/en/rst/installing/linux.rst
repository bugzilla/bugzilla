.. _linux:

Linux
#####

Some Linux distributions include Bugzilla and its dependencies in their
package management systems. If you have root access, installing Bugzilla on
any Linux system could be as simple as finding the Bugzilla package in the
package management application and installing it. There may be a small bit
of additional configuration required.

If you are installing your machine from scratch, :ref:`quick-start` may be
the best instructions for you.

.. todo:: What's our current position on Debian/Ubuntu packages of Bugzilla? Are
          there any, and are they any good?

.. todo:: Which versions of RHEL have packages new enough for us to support them?

.. todo:: What's the right order for all the following steps?

Install Packages
================

Use your distribution's package manager to install Perl, your preferred
database engine (MySQL if in doubt), and a webserver (Apache if in doubt).

The commands below will install those things and some of Bugzilla's other
prerequisites as well. If you find a package doesn't install or the name
is not found, just remove it from the list and reissue the command.

Fedora and Red Hat
------------------

:command:`yum install httpd mysql-server mod_perl mod_perl-devel httpd-devel
graphviz patchutils gcc perl-DateTime perl-Template-Toolkit perl-Email-Send
perl-Email-MIME perl-GD perl-Chart perl-Template-GD perl-GDGraph
perl-GDTextUtil perl-PatchReader perl-MIME-tools perl-LDAP perl-Authen-SASL
perl-RadiusPerl perl-SOAP-Lite perl-JSON-RPC perl-JSON-XS perl-Test-Taint
perl-HTML-Scrubber perl-Email-MIME-Attachment-Stripper perl-Email-Reply
perl-TheSchwartz perl-Daemon-Generic perl-Math-Random-Secure perl-YAML
perl-Class-Inspector`

If you are running RHEL6, you will have to enable the "RHEL Server Optional"
channel in RHN to get some of those packages. 

Ubuntu and Debian
-----------------

:command:`apt-get install git nano`

:command:`apt-get install apache2 mysql-server libappconfig-perl
libdate-calc-perl libtemplate-perl libmime-perl build-essential
libdatetime-timezone-perl libdatetime-perl libemail-send-perl
libemail-mime-perl libemail-mime-modifier-perl libdbi-perl libdbd-mysql-perl
libcgi-pm-perl libmath-random-isaac-perl libmath-random-isaac-xs-perl
apache2-mpm-prefork libapache2-mod-perl2 libapache2-mod-perl2-dev
libchart-perl libxml-perl libxml-twig-perl perlmagick libgd-graph-perl
libtemplate-plugin-gd-perl libsoap-lite-perl libhtml-scrubber-perl
libjson-rpc-perl libdaemon-generic-perl libtheschwartz-perl
libtest-taint-perl libauthen-radius-perl libfile-slurp-perl
libencode-detect-perl libmodule-build-perl libnet-ldap-perl
libauthen-sasl-perl libtemplate-perl-doc libfile-mimeinfo-perl
libhtml-formattext-withlinks-perl libgd-dev lynx-cur`

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

.. todo:: Is this true, if they are installing modules locally?

To check whether you have all the required modules and what is still missing,
run:

:command:`./checksetup.pl --check-modules`

You can run this command as many times as necessary.

Install all missing modules locally like this:

:command:`./install-module.pl --all`

Or, you can pass an individual module name:

:command:`./install-module.pl <modulename>`

.. note:: If you are using a package-based distribution, and attempting to
   install the Perl modules from CPAN (e.g. by using
   :file:`install-module.pl`), you may need to install the "development"
   packages for MySQL and GD before attempting to install the related Perl
   modules. The names of these packages will vary depending on the specific
   distribution you are using, but are often called
   :file:`<packagename>-devel`.

   .. todo:: Give examples for Debian/Ubuntu and RedHat?

.. _config-webserver:

Web Server
==========

Any web server that is capable of running CGI scripts can be made to work.
We have specific instructions for the following:

.. toctree::
   :maxdepth: 1

   apache

You can run :command:`testserver.pl http://bugzilla-url/` from the command
line to check if your web server is correctly configured.

.. todo:: Does this work before doing any localconfig stuff?

.. _config-database:

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

Load this file in your editor. You will need to check/change ``$db_driver``
and ``$db_pass``, which are respectively the type of the database you are
using and the password for the ``bugs`` database user you have created.
``$db_driver`` can be either ``mysql``, ``Pg`` (PostgreSQL), ``Oracle`` or
``Sqlite``. All values are case-sensitive.

Set the value of ``$webservergroup`` to the group your web server runs as.
The default is ``apache``, which is correct for Red Hat and Fedora. On Debian
and Ubuntu, the correct value is ``www-data``.

The other options in the :file:`localconfig` file are documented by their
accompanying comments. If you have a non-standard database setup, you may
need to change one or more of the other ``$db_*`` parameters.

.. note:: If you are using Oracle, ``$db_name`` should be set to
   the SID name of your database (e.g. "XE" if you are using Oracle XE).

checksetup.pl
=============

Next, run :file:`checksetup.pl` an additional time. It reconfirms
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

Next, do the :ref:`post-install-config`.

.. todo:: How to we integrate the below (copied from the wiki)?

Gentoo
======

Gentoo pulls in all dependencies and, if you don't have the vhosts USE flag enabled, installs Bugzilla to /var/www/localhost/bugzilla when you issue:

<code># emerge -av bugzilla</code>

You will then have to configure and install your database according to your needs:

For a first time MySQL install:

<code># mysql_install_db</code>

Else:

<code># mysql -u root -p<br />
mysql>CREATE DATABASE databasename;<br />
mysql>GRANT <privs> ON databasename.* to 'bugzillauser'@'hostname' identified by 'pa$$w0rd';</code>
 
Fedora
======

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
