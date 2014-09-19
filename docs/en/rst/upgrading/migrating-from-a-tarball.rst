.. _migrating-from-a-tarball:

Migrating from a Tarball
########################

.. todo:: Need to check the diff command in the tarball case using a real
          tarball and git checkout

.. |diffcommand|   replace:: :command:`diff -ru -x data -x .git ../bugzilla-new . > patch.diff`
.. |extstatusinfo| replace:: Copy across any subdirectories which do not exist
                             in your new install.

The procedure to migrate to Git is as follows. The idea is to switch without
changing the version of Bugzilla you are using, to minimise the risk of
conflict or problems. Any major upgrade can then happen as a separate step. 

Find Your Current Bugzilla Version
==================================

First, you need to find what version of Bugzilla you are using. It should be
in the top right corner of the front page but, if not, open the file
:file:`Bugzilla/Constants.pm` in your Bugzilla directory and search for
:code:`BUGZILLA_VERSION`.

.. include:: migrating-from-2.rst.inc
