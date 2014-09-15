.. _post-install-config:

Post-Installation Configuration
###############################

Bugzilla is configured in the Administration Parameters. Log in with the
administrator account you defined in the last :file:`checksetup.pl` run,
then click :guilabel:`Administration` in the header, and then
:guilabel:`Parameters`. You will see the different parameter sections
down the left hand side of the page.

Essential
=========

There are a few parameters which it is very important to define (or
explicitly decide not to change).

The first set of these are in the :guilabel:`Required Settings` section.

* :param:`urlbase`: this is the URL by which people should access
  Bugzilla's front page.
* :param:`sslbase`: if you have configured SSL on your Bugzilla server,
  this is the SSL URL by which people should access Bugzilla's front page.
* :param:`ssl_redirect`: Set this if you want everyone to be redirected
  to use the SSL version. Recommended if you have set up SSL.
* :param:`cookiebase`: Bugzilla uses cookies to remember who each user is.
  In order to set those cookies in the correct scope, you may need to set a
  cookiebase. If your Bugzilla is at the root of your domain, you don't need
  to change the default value.

You will also need to tell Bugzilla how to :ref:`send email <email>`.

You may want to put your email address in the :param:`maintainer`
parameter in the :guilabel:`General` section. This will then let people
know who to contact if they see problems or hit errors.

If you don't want just anyone able to read your Bugzilla, set the
:param:`requirelogin` parameter in the :guilabel:`User Authentication`
section, and change or clear the :param:`createemailregexp` parameter.

.. _optional-features:

Optional
========

XXXHACKME

Bugzilla has a number of optional features. This section describes how
to configure or enable them.

Bug Graphs
----------

If you have installed the necessary Perl modules you
can start collecting statistics for the nifty Bugzilla
graphs.

::

    # crontab -e

This should bring up the crontab file in your editor.
Add a cron entry like this to run
:file:`collectstats.pl`
daily at 5 after midnight:

.. code-block:: none

    5 0 * * * cd <your-bugzilla-directory> && ./collectstats.pl

After two days have passed you'll be able to view bug graphs from
the Reports page.

.. note:: Windows does not have 'cron', but it does have the Task
   Scheduler, which performs the same duties. There are also
   third-party tools that can be used to implement cron, such as
   `nncron <http://www.nncron.ru/>`_.

.. _installation-whining-cron:

The Whining Cron
----------------

What good are
bugs if they're not annoying? To help make them more so you
can set up Bugzilla's automatic whining system to complain at engineers
which leave their bugs in the CONFIRMED state without triaging them.

This can be done by adding the following command as a daily
crontab entry, in the same manner as explained above for bug
graphs. This example runs it at 12.55am.

.. code-block:: none

    55 0 * * * cd <your-bugzilla-directory> && ./whineatnews.pl

.. note:: Windows does not have 'cron', but it does have the Task
   Scheduler, which performs the same duties. There are also
   third-party tools that can be used to implement cron, such as
   `nncron <http://www.nncron.ru/>`_.

.. _installation-whining:

Whining
-------

Users can configure Bugzilla to regularly annoy
them at regular intervals, by having Bugzilla execute saved searches
at certain times and emailing the results to the user.  This is known
as "Whining".  The process of configuring Whining is described
in :ref:`whining`, but for it to work a Perl script must be
executed at regular intervals.

This can be done by adding the following command as a daily
crontab entry, in the same manner as explained above for bug
graphs. This example runs it every 15 minutes.

.. code-block:: none

    */15 * * * * cd <your-bugzilla-directory> && ./whine.pl

.. note:: Whines can be executed as often as every 15 minutes, so if you specify
   longer intervals between executions of whine.pl, some users may not
   be whined at as often as they would expect.  Depending on the person,
   this can either be a very Good Thing or a very Bad Thing.

.. note:: Windows does not have 'cron', but it does have the Task
   Scheduler, which performs the same duties. There are also
   third-party tools that can be used to implement cron, such as
   `nncron <http://www.nncron.ru/>`_.

.. _multiple-bz-dbs:

Multiple Bugzilla databases with a single installation
------------------------------------------------------

The previous instructions referred to a standard installation, with
one unique Bugzilla database. However, you may want to host several
distinct installations, without having several copies of the code. This is
possible by using the PROJECT environment variable. When accessed,
Bugzilla checks for the existence of this variable, and if present, uses
its value to check for an alternative configuration file named
:file:`localconfig.<PROJECT>` in the same location as
the default one (:file:`localconfig`). It also checks for
customized templates in a directory named
:file:`<PROJECT>` in the same location as the
default one (:file:`template/<langcode>`). By default
this is :file:`template/en/default` so PROJECT's templates
would be located at :file:`template/en/PROJECT`.

To set up an alternate installation, just export PROJECT=foo before
running :command:`checksetup.pl` for the first time. It will
result in a file called :file:`localconfig.foo` instead of
:file:`localconfig`. Edit this file as described above, with
reference to a new database, and re-run :command:`checksetup.pl`
to populate it. That's all.

Now you have to configure the web server to pass this environment
variable when accessed via an alternate URL, such as virtual host for
instance. The following is an example of how you could do it in Apache,
other Webservers may differ.

.. code-block:: apache

    <VirtualHost 212.85.153.228:80>
    ServerName foo.bar.baz
    SetEnv PROJECT foo
    Alias /bugzilla /var/www/bugzilla
    </VirtualHost>

Don't forget to also export this variable before accessing Bugzilla
by other means, such as cron tasks for instance.

