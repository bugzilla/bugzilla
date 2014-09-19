.. _upgrading-from-cvs:

Upgrading from CVS
##################

.. |updatecommand| replace:: :command:`cvs update -rBUGZILLA-$VERSION-STABLE -dP`
.. |diffcommand|   replace:: :command:`cvs diff -puN > patch.diff`
.. |extstatusinfo| replace:: The command :command:`cvs status extensions/` should help you work out what you added, if anything.

.. include:: upgrading-from-1.rst.inc
.. include:: upgrading-from-2.rst.inc


