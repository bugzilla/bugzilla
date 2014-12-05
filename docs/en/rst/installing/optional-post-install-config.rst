.. _optional-post-install-config:

Optional Post-Install Configuration
###################################

Bugzilla has a number of optional features. This section describes how
to configure or enable them.

.. _recurring-tasks:

Recurring Tasks
===============

Several of the below features require you to set up a script to run at
recurring intervals. The method of doing this varies by operating system.

Linux
-----

Run:

:command:`crontab -e`

This should bring up the crontab file in your editor. Add the relevant
cron line from the sections below in order to enable the corresponding
feature.

Windows
-------

Windows comes with a Task Scheduler. To run a particular script, do the
following:

#. :guilabel:`Control Panel` --> :guilabel:`Scheduled Tasks` -->
   :guilabel:`Add Scheduled Task`

#. Next

#. Browse

#. Find :file:`perl.exe` (normally :file:`C:\\Perl\\bin\\perl.exe`)

#. Give the task a name, such as "Bugzilla <scriptname>"

#. Request the task be performed at your desired time and interval

#. If you're running Apache as a user, not as SYSTEM, enter that user
   here. Otherwise you're best off creating an account that has write access
   to the Bugzilla directory and using that

#. Tick "Open Advanced Properties.." and click Finish

#. Append the script name to the end of the "Run" field. eg
   :command:`C:\\Perl\\bin\\perl.exe C:\\Bugzilla\\<scriptname>`

#. Change "start in" to the Bugzilla directory

.. _installation-bug-graphs:

Bug Graphs
==========

If you have installed the necessary Perl modules, as indicated by
:file:`checksetup.pl`, you can ask Bugzilla to regularly collect statistics
so that you can see graphs and charts.

On Linux, use a cron line as follows:

.. code-block:: none

    5 0 * * * cd <your-bugzilla-directory> && ./collectstats.pl

On Windows, schedule the :file:`collectstats.pl` script to run daily.

After two days have passed you'll be able to view bug graphs from
the Reports page.

.. _installation-whining:

Whining
=======

Users can configure Bugzilla to annoy them at regular intervals, by having
Bugzilla execute saved searches at certain times and emailing the results to
the user.  This is known as "Whining".  The details of how a user configures
Whining is described in :ref:`whining`, but for it to work a Perl script must
be executed at regular intervals.

On Linux, use a cron line as follows:

.. code-block:: none

    */15 * * * * cd <your-bugzilla-directory> && ./whine.pl

On Windows, schedule the :file:`whine.pl` script to run every 15 minutes.

.. _installation-whining-cron:

Whining at Untriaged Bugs
=========================

It's possible for bugs to languish in an untriaged state. Bugzilla has a
specific system to issue complaints about this particular problem to all the
relevant engineers automatically by email.

On Linux, use a cron line as follows:

.. code-block:: none

    55 0 * * * cd <your-bugzilla-directory> && ./whineatnews.pl

On Windows, schedule the :file:`whineatnews.pl` script to run daily.

Dependency Graphs
=================

Bugzilla can draw graphs of the dependencies (depends on/blocks relationships)
between bugs, if you install a package called :file:`dot`.

Linux
-----

Put the complete path to the :file:`dot` command (from the ``graphviz``
package) in the :param:`webdotbase` parameter. E.g. :paramval:`/usr/bin/dot`.

Windows
-------

Download and install Graphviz from
`the Graphviz website <http://www.graphviz.org/Download_windows.php>`_. Put
the complete path to :file:`dot.exe` in the :param:`webdotbase` parameter,
using forward slashes as path separators. E.g.
:paramval:`C:/Program Files/ATT/Graphviz/bin/dot.exe`.
