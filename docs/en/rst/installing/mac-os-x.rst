.. _mac-os-x:

Mac OS X
########

.. _macosx-install-packages:

Install Packages
================

OS X 10.7 provides Perl 5.12 and Apache 2.2. Install the following additional
packages:

* git: Download an installer from
  `the git website <http://www.git-scm.com/downloads>`_. 
* MySQL: Download an installer from
  `the MySQL website <http://dev.mysql.com/downloads/mysql/>`_.

.. _macosx-install-bzfiles:

Bugzilla
========

The best way to get Bugzilla is to check it out from git:

:command:`git clone https://git.mozilla.org/bugzilla/bugzilla`

Run the above command in your home directory. This will place Bugzilla in
the directory :file:`$HOME/bugzilla`.

If that's not possible, you can
`download a tarball of Bugzilla <http://www.bugzilla.org/download/>`_.

.. _macosx-libraries:

Additional System Libraries
===========================

Apple does not include the GD library with Mac OS X. Bugzilla needs this if
you want to display bug graphs.

You can use `MacPorts <http://www.macports.org/>`_ or
`Fink <http://sourceforge.net/projects/fink/>`_, both of which install common
Unix programs on Mac OS X.

Follow the instructions for setting up MacPorts or Fink. Once you have one
installed, use it to install the :file:`gd2` package.

Fink will prompt you for a number of dependencies, type 'y' and hit
enter to install all of the dependencies and then watch it work. You will
then be able to use CPAN to install the GD Perl module.

.. note:: To prevent creating conflicts with the software that Apple
   installs by default, Fink creates its own directory tree at :file:`/sw`
   where it installs most of
   the software that it installs. This means your libraries and headers
   will be at :file:`/sw/lib` and :file:`/sw/include` instead
   of :file:`/usr/lib` and :file:`/usr/include`. When the
   Perl module config script asks where your :file:`libgd`
   is, be sure to tell it :file:`/sw/lib`.

.. _macosx-install-perl-modules:

Perl Modules
============

Bugzilla requires a number of Perl modules. On Mac OS X, the easiest thing to
do is to install local copies (rather than system-wide copies) of any ones
that you don't already have. However, if you do want to install them
system-wide, run the below commands as root with the :command:`--global`
option.

To check whether you have all the required modules and what is still missing,
run:

:command:`perl checksetup.pl --check-modules`

You can run this command as many times as necessary.

Install all missing modules locally like this:

:command:`perl install-module.pl --all`

.. _macosx-config-webserver:

Web Server
==========

Any web server that is capable of running CGI scripts can be made to work.
We have specific configuration instructions for the following:

* :ref:`apache`

You'll need to create a symbolic link so the webserver can see Bugzilla:

:command:`cd /Library/WebServer/Documents`

:command:`sudo ln -s $HOME/bugzilla bugzilla`

In :guilabel:`System Preferences` --> :guilabel:`Sharing`, enable the
:guilabel:`Web Sharing` checkbox to start Apache. 

.. _macosx-config-database:

Database Engine
===============

Bugzilla supports MySQL, PostgreSQL, Oracle and SQLite as database servers.
You only require one of these systems to make use of Bugzilla. MySQL is
most commonly used on Mac OS X. Configure your server according to the
instructions below:

.. todo:: Has anyone tried anything other than MySQL on Mac OS X?

* :ref:`mysql`
* :ref:`postgresql`
* :ref:`oracle`
* :ref:`sqlite`

.. |checksetupcommand| replace:: :command:`perl checksetup.pl`
.. |testservercommand| replace:: :command:`perl testserver.pl http://<your-bugzilla-server>/`

.. include:: installing-end.inc.rst

Next, do the :ref:`essential-post-install-config`.
