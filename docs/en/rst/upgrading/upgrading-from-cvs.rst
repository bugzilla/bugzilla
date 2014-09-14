.. _upgrading-from-cvs:

Upgrading from CVS
##################

XXX Fill in commands from https://wiki.mozilla.org/Bugzilla:Moving_From_CVS_To_Bazaar

.. |updatecommand| replace:: :command:`bzr up -r tag:bugzilla-$VERSION`
.. |diffcommand|   replace:: :command:`bzr diff > patch.diff`
.. |extstatusinfo| replace:: The command :command:`bzr status extensions/` should help you work out what you added, if anything.

.. include:: upgrading-from-1.rst
.. include:: get-from-git.rst
.. include:: upgrading-from-2.rst


