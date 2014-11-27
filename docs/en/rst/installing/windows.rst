.. _windows:

Windows
#######

Making Bugzilla work on Windows is more difficult than making it work on Unix,
fewer Bugzilla developers use it and so it's less well supported. We would
particularly recommend against doing it for a large site. However, if
you are still determined to go ahead, here's how.

.. windows-install-perl:

ActiveState Perl
================

ActiveState make a popular distribution of Perl for Windows.

Download the ActiveState Perl 5.12.4 or higher MSI installer from the
`ActiveState website <http://www.activestate.com/activeperl/downloads>`_.

ActiveState Perl uses a standard Windows Installer. Install, sticking with
the defaults, which will install Perl into :file:`C:\\Perl`. It is not
recommended to install Perl into a directory containing a space, such as
:file:`C:\\Program Files`.

Once the install has completed, log out and log in again to pick up the
changes to the ``PATH`` environment variable.

.. _windows-install-bzfiles:

Bugzilla
========

The best way to get Bugzilla is to check it out from git. Download and install
git from the `git website <http://git-scm.com/download>`_, and then run:

:command:`git clone --branch bugzilla-X.X-stable https://git.mozilla.org/bugzilla/bugzilla C:\\bugzilla`

where "X.X" is the 2-digit version number of the stable release of Bugzilla
that you want (e.g. 4.4).

The rest of this documentation assumes you have installed Bugzilla into
:file:`C:\\bugzilla`. Adjust paths appropriately if not.

If it's not possible to use git (e.g. because your Bugzilla machine has no
internet access), you can
`download a tarball of Bugzilla <http://www.bugzilla.org/download/>`_ and
copy it across. Bugzilla comes as a 'tarball' (:file:`.tar.gz` extension),
which any competent Windows archiving tool should be able to open.

.. windows-install-perl-modules:

Perl Modules
============

Bugzilla requires a number of perl modules to be installed. They are
available in the ActiveState repository, and are installed with the
:file:`ppm` tool. You can either use it on the command line, as below,
or just type :command:`ppm`, and you will get a GUI.

If you use a proxy server or a firewall you may have trouble running PPM.
This is covered in the
`ActivePerl FAQ <http://aspn.activestate.com/ASPN/docs/ActivePerl/faq/ActivePerl-faq2.html#ppm_and_proxies>`_.

Install the following modules with:

:command:`ppm install <modulename>`

* CGI.pm
* Digest-SHA
* TimeDate
* DateTime
* DateTime-TimeZone
* DBI
* Template-Toolkit
* Email-Sender
* Email-MIME
* URI
* List-MoreUtils
* Math-Random-ISAAC
* File-Slurp
* JSON-XS
* Win32
* Win32-API

The following modules enable various optional Bugzilla features; try and
install them, but don't worry too much to begin with if you can't get them
installed:

* GD
* Chart
* Template-GD
* GDTextUtil
* GDGraph
* MIME-tools
* libwww-perl
* XML-Twig
* PatchReader
* perl-ldap
* Authen-SASL
* Net-SMTP-SSL
* RadiusPerl
* SOAP-Lite
* XMLRPC-Lite
* JSON-RPC
* Test-Taint
* HTML-Parser
* HTML-Scrubber
* Encode
* Encode-Detect
* Email-Reply
* HTML-FormatText-WithLinks
* TheSchwartz
* Daemon-Generic
* mod_perl
* Apache-SizeLimit
* File-MimeInfo
* IO-stringy
* Cache-Memcached
* Text-Markdown
* File-Copy-Recursive
* GraphViz

.. warning:: These lists have been extracted from Bugzilla's source code and
             have not been tested. Please let us know if you find errors in it
             of any sort.

.. note:: The :file:`install-module.pl` script doesn't work with ActivePerl
   on Windows.

.. _windows-config-webserver:

Web Server
==========

Any web server that is capable of running CGI scripts can be made to work.
We have specific instructions for the following:

* :ref:`apache-windows`
* :ref:`iis`

.. windows-config-database:

Database Engine
===============

Bugzilla supports MySQL, PostgreSQL, Oracle and SQLite as database servers.
You only require one of these systems to make use of Bugzilla. MySQL is
most commonly used, and is the only one for which Windows instructions have
been tested. SQLite is good for trial installations as it requires no
setup. Configure your server according to the instructions below:

* :ref:`mysql`
* :ref:`postgresql`
* :ref:`oracle`
* :ref:`sqlite`

.. |checksetupcommand| replace:: :command:`checksetup.pl`
.. |testservercommand| replace:: :command:`testserver.pl http://<your-bugzilla-server>/`

.. include:: installing-end.inc.rst

If you don't see the main Bugzilla page, but instead see "It works!!!",
then somehow your Apache has not picked up your modifications to
:file:`httpd.conf`. If you are on Windows 7 or later, this could be due to a
new feature called "VirtualStore". `This blog post
<http://blog.netscraps.com/bugs/apache-httpd-conf-changes-ignored-in-windows-7.html>`_
may help to solve the problem.

If you get an "Internal Error..." message, it could be that
``ScriptInterpreterSource Registry-Strict`` is not set in your
:ref:`Apache configuration <apache-windows>`. Check again if it is set
properly.

Next, do the :ref:`essential-post-install-config`.
