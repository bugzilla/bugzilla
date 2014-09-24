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

.. _linux-install-packages:

Install Packages
================

Use your distribution's package manager to install Perl, your preferred
database engine (MySQL if in doubt), and a webserver (Apache if in doubt).
Some distributions even have a Bugzilla package, although that will vary
in age.

The commands below will install those things and some of Bugzilla's other
prerequisites as well. If you find a package doesn't install or the name
is not found, just remove it from the list and reissue the command. If you
want to use a different database or webserver, substitute the package
names as appropriate.

Fedora and Red Hat
------------------

The following command will install Red Hat's packaged version of Bugzilla:

:command:`yum install bugzilla httpd mysql-server`

However, if you go this route, you need to read :bug:`415605`, which details
some problems with the Email::Send package. Then, you can skip to
:ref:`configuring your database <linux-config-database>`. It may be useful to
know that Fedora stores the Bugzilla files in :file:`/usr/share/bugzilla`, so
that's where you'll run :file:`checksetup.pl`.

If you want to install a version of Bugzilla from the Bugzilla project, you
will instead need:

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

.. todo:: Add Sqlite RPMs

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
libhtml-formattext-withlinks-perl libgd-dev lynx-cur graphviz`

.. todo:: Add Sqlite debs

Gentoo
------

:command:`emerge -av bugzilla`

will install Bugzilla and all its dependencies. If you don't have the vhosts
USE flag enabled, Bugzilla will end up in :file:`/var/www/localhost/bugzilla`.

Then, you can skip to :ref:`configuring your database
<linux-config-database>`.

.. _linux-install-perl:

Perl
====

Test which version of Perl you have installed with:
::

    $ perl -v

Bugzilla requires at least Perl |min-perl-ver|.

.. _linux-install-bzfiles:

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

.. todo:: Why is this necessary? What does the webserver write there before
          checksetup.pl is run?

.. _linux-install-perl-modules:

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

.. _linux-config-webserver:

Web Server
==========

Any web server that is capable of running CGI scripts can be made to work.
We have specific configuration instructions for the following:

.. toctree::
   :maxdepth: 1

   apache

.. _linux-config-database:

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

.. |checksetupcommand| replace:: :command:`./checksetup.pl`
.. |testservercommand| replace:: :command:`./testserver.pl http://<your-bugzilla-server>/`

.. include:: installing-end.inc.rst

Next, do the :ref:`essential-post-install-config`.
