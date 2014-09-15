.. _upgrading-with-git:

Upgrading with Git
##################

Upgrading to new Bugzilla releases is very simple, and you can upgrade
from any version to any later version in one go - there is no need for
intermediate steps. There is a script named :file:`checksetup.pl` included
with Bugzilla that will automatically do all of the database migration
for you.

.. warning:: Upgrading is a one-way process. You cannot "downgrade" an
   upgraded Bugzilla. If you wish to revert to the old Bugzilla
   version for any reason, you will have to restore your database
   from a backup. Those with critical data or large installations may wish
   to trial the upgrade on a development server first, using a copy of the
   production data and configuration.

In the commands below, ``$BUGZILLA_HOME`` represents the directory
in which Bugzilla is installed.

.. _upgrade-before:

Before You Upgrade
==================

Before you start your upgrade, there are a few important
steps to take:

#. Read the
   `Release Notes <http://www.bugzilla.org/releases/>`_ of the version you're
   upgrading to and all intermediate versions, particularly the "Notes for
   Upgraders" sections, if present.

   XXX We need to make these more accessible - they are currently rather hard
   to find. We could collate them on a single page with no intervening cruft.

#. Run the :ref:`sanity-check` on your installation. Attempt to fix all
   warnings that the page produces before you go any further, or it's
   possible that you may experience problems during your upgrade.

#. Shut down your Bugzilla installation by putting some explanatory text
   in the :param:`shutdownhtml` parameter.

#. Make all necessary :ref:`backups`.
   *THIS IS VERY IMPORTANT*. If anything goes wrong during the upgrade,
   having a backup allows you to roll back to a known good state.

.. _upgrade-modified:

Customized Bugzilla?
--------------------

If you have modified the code or templates of your Bugzilla,
then upgrading requires a bit more thought and effort than the simple process
below. A discussion of the various methods of updating compared with
degree and methods of local customization can be found in
:ref:`template-method`.

The larger the jump you are trying to make, the more difficult it
is going to be to upgrade if you have made local customizations.
Upgrading from 4.2 to 4.2.1 should be fairly painless even if
you are heavily customized, but going from 2.18 to 4.2 is going
to mean a fair bit of work re-writing your local changes to use
the new files, logic, templates, etc. If you have done no local
changes at all, however, then upgrading should be approximately
the same amount of work regardless of how long it has been since
your version was released.

XXX Need more here

.. _upgrade-files:

Getting The New Bugzilla
========================

:command:`cd $BUGZILLA_HOME`

:command:`git checkout`

:command:`git pull`

XXX How to pull latest stable?

.. _upgrade-database:

Upgrading the Database
======================

Run :file:`checksetup.pl`. This will do everything required to convert
your existing database and settings to the new version.

:command:`cd $BUGZILLA_HOME`

:command:`./checksetup.pl`

   .. warning:: For some upgrades, running :file:`checksetup.pl` on a large
      installation (75,000 or more bugs) can take a long time,
      possibly several hours, if e.g. indexes need to be rebuilt. If this
      length of downtime would be a problem for you, you can determine
      timings for your particular situation by doing a test upgrade on a
      development server with the production data.

.. _upgrade-finish:

Finishing The Upgrade
=====================

#. Reactivate Bugzilla by clear the text that you put into the
   :param:`shutdownhtml` parameter.

#. Run a :ref:`sanity-check` on your
   upgraded Bugzilla. It is recommended that you fix any problems
   you see immediately. Failure to do this may mean that Bugzilla
   will not work entirely correctly. 
