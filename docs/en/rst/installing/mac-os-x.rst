.. _mac-os-x:

Mac OS X
########

`<https://wiki.mozilla.org/Bugzilla:Mac_OS_X_installation>`_ is what we have
right now...

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
