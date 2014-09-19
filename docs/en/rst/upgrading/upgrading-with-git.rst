.. _upgrading-with-git:

Upgrading with Git
##################

Upgrading to new Bugzilla releases is very simple, and you can upgrade
from any version to any later version in one go - there is no need for
intermediate steps. There is a script named :file:`checksetup.pl` included
with Bugzilla that will automatically do all of the database migration
for you.

.. include:: upgrading-with-1.rst.inc

You can see if you have local code customizations using:

:command:`git diff`

If that comes up empty, then run:

:command:`git log | head`

and see if the last commit looks like one made by the Bugzilla team, or
by you. If it looks like it was made by us, then you have made no local
code customizations.

.. _start-upgrade-git:

Starting the Upgrade
====================

When you are ready to go:

#. Shut down your Bugzilla installation by putting some explanatory text
   in the :param:`shutdownhtml` parameter.

#. Make all necessary :ref:`backups <backups>`.
   *THIS IS VERY IMPORTANT*. If anything goes wrong during the upgrade,
   having a backup allows you to roll back to a known good state.

.. _upgrade-files-git:

Getting The New Bugzilla
========================

In the commands below, ``$BUGZILLA_HOME`` represents the directory
in which Bugzilla is installed.

:command:`cd $BUGZILLA_HOME`

:command:`git checkout`

:command:`git pull`

.. todo:: What is the best way to pull latest stable?

If you have local code customizations, git will attempt to merge them. If
it fails, then you should implement the plan you came up with when you
detected these customizations in the step above, before you started the
upgrade.

.. include:: upgrading-with-2.rst.inc
