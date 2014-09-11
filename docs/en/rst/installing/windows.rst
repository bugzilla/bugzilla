.. _windows:

Windows
#######

Microsoft Windows
=================

Making Bugzilla work on Windows is more difficult than making it
work on Unix.  For that reason, we still recommend doing so on a Unix
based system such as GNU/Linux.  That said, if you do want to get
Bugzilla running on Windows, you will need to make the following
adjustments. A detailed step-by-step
`installation guide for Windows <https://wiki.mozilla.org/Bugzilla:Win32Install>`_ is also available
if you need more help with your installation.


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
Add a User to Oracle



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
