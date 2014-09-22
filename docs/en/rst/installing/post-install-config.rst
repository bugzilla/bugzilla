.. _post-install-config:

Post-Installation Configuration
###############################

Bugzilla is configured in the Administration Parameters. Log in with the
administrator account you defined in the last :file:`checksetup.pl` run,
then click :guilabel:`Administration` in the header, and then
:guilabel:`Parameters`. You will see the different parameter sections
down the left hand side of the page.

.. _config-essential-params:

Essential Parameters
====================

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

You may want to put your email address in the :param:`maintainer`
parameter in the :guilabel:`General` section. This will then let people
know who to contact if they see problems or hit errors.

If you don't want just anyone able to read your Bugzilla, set the
:param:`requirelogin` parameter in the :guilabel:`User Authentication`
section, and change or clear the :param:`createemailregexp` parameter.

You will also need to set appropriate parameters so Bugzilla knows how to
:ref:`send email <email>`.

.. _config-products:

Products, Components, Versions and Milestones
=============================================

Bugs in Bugzilla are categorised into Products and, inside those Products,
Components (and, optionally, if you turn on the :param:`useclassifications`
parameter, Classifications as a level above Products).

Bugzilla comes with a single Product, called "TestProduct", which contains a
single component, imaginatively called "TestComponent". You will want to
create your own Products and their Components. It's OK to have just one
Component inside a Product. Products have Versions (which represents the
version of the software in which a bug was found) and Target Milestones
(which represent the future version of the product in which the bug is
hopefully to be fixed - or, for RESOLVED bugs, was fixed. You may also want
to add some of those.

Once you've created your own, you will want to delete TestProduct (which
will delete TestComponent automatically). Note that if you've filed a bug in
TestProduct to try Bugzilla out, you'll need to move it elsewhere before it's
possible to delete TestProduct.

.. _optional-features:

Optional Features
=================

Bugzilla has a number of optional features. This section describes how
to configure or enable them.

Bug Graphs
----------

If you have installed the necessary Perl modules, as indicated by
:file:`checksetup.pl`, you can ask Bugzilla to regularly collect statistics
so that you can see graphs and charts. Run:

:command:`crontab -e`

This should bring up the crontab file in your editor. Add a cron entry like
this to run :file:`collectstats.pl` daily at 5 after midnight:

.. code-block:: none

    5 0 * * * cd <your-bugzilla-directory> && ./collectstats.pl

After two days have passed you'll be able to view bug graphs from
the Reports page.

Windows does not have 'cron', but it does have the Task Scheduler, which
performs the same duties. There are also third-party tools that can be used
to implement cron, such as `nncron <http://www.nncron.ru/>`_.

.. _installation-whining:

Whining
-------

Users can configure Bugzilla to annoy them at regular intervals, by having
Bugzilla execute saved searches at certain times and emailing the results to
the user.  This is known as "Whining".  The details of how a user configures
Whining is described in :ref:`whining`, but for it to work a Perl script must
be executed at regular intervals.

This can be done by adding the following repeating command, in
the same manner as explained above for bug graphs. This example, using cron
syntax, runs it every 15 minutes, which is the recommended interval.

.. code-block:: none

    */15 * * * * cd <your-bugzilla-directory> && ./whine.pl

.. _installation-whining-cron:

Whining at Untriaged Bugs
-------------------------

It's possible for bugs to languish in an untriaged state. Bugzilla has a
specific system to issue complaints about this particular problem to all the
relevant engineers automatically by email.

This can be done by adding the following repeating command, in
the same manner as explained above for bug graphs. This example, using cron
syntax, runs it at 12.55am:

.. code-block:: none

    55 0 * * * cd <your-bugzilla-directory> && ./whineatnews.pl

.. _multiple-bz-dbs:

Running Multiple Bugzillas from a Single Code Installation
----------------------------------------------------------

This is a somewhat specialist feature; if you don't know whether you need it,
you don't. It is useful to admins who want to run many separate instances of
Bugzilla from a single codebase.

This is possible by using the ``PROJECT`` environment variable. When accessed,
Bugzilla checks for the existence of this variable, and if present, uses
its value to check for an alternative configuration file named
:file:`localconfig.<PROJECT>` in the same location as
the default one (:file:`localconfig`). It also checks for
customized templates in a directory named
:file:`<PROJECT>` in the same location as the
default one (:file:`template/<langcode>`). By default
this is :file:`template/en/default` so ``PROJECT``'s templates
would be located at :file:`template/en/PROJECT`.

To set up an alternate installation, just export ``PROJECT=foo`` before
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

    <VirtualHost 12.34.56.78:80>
        ServerName bugzilla.example.com
        SetEnv PROJECT foo
    </VirtualHost>

Don't forget to also export this variable before accessing Bugzilla
by other means, such as repeating tasks like those above.
