.. _upgrading-with-a-tarball:

Upgrading with a Tarball
########################

If you are unable (or unwilling) to use Git, another option that's
always available is to obtain a tarball of the latest version from our
website and upgrade your Bugzilla installation from that.

Download Bugzilla
=================

Download a copy of the latest version of Bugzilla from the
`Download Page <http://www.bugzilla.org/download/>`_ into a separate
directory (which we will call :file:`bugzilla-new`) alongside your existing
Bugzilla installation (which we will assume is in a directory called
:file:`bugzilla`).

.. |diffcommand|   replace:: :command:`diff -u > patch.diff`
.. |extstatusinfo| replace:: With no SCM to help you, you will have to
                             work out by hand which extensions came with
                             Bugzilla and which you added.

.. include:: upgrading-from-2.rst
