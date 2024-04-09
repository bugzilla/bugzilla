.. highlight:: console

.. _installing:
   
==================================
Installation and Maintenance Guide
==================================

.. warning:: This section, as is, is copied over from the mainline Bugzilla 
   install documentation. There are significant changes in how 
   Harmony should be deployed. As such, do not refer to this 
   documentation for now, but use the `Docker instructions 
   <https://github.com/bugzilla/harmony/blob/main/docker/README.md>`_
   as a guide. The Bugzilla team are revising this section. 

.. note:: If you just want to *use* Bugzilla,
   you do not need to install it. None of this chapter is relevant to
   you. Ask your Bugzilla administrator for the URL to access it from
   your web browser. See the :ref:`using`.

Bugzilla can be installed under Linux, Windows, Mac OS X, and perhaps other
operating systems. However, if you are setting it up on a dedicated machine
and you have control of the operating system to use, the Bugzilla team
wholeheartedly recommends Linux as an extremely versatile, stable, and robust
operating system that provides an ideal environment for Bugzilla. In that
case, read the :ref:`Quick Start instructions <quick-start>`.

If you wish to run a local evaluation instance of Bugzilla, see the :ref:`Docker instructions <docker>`.

.. toctree::
   :maxdepth: 1

   docker
   quick-start
   linux
   windows
   mac-os-x
   web_server
   db_server
   essential-post-install-config
   optional-post-install-config
   migrating
   moving
   upgrading
   backups
   sanity-check
   merging-accounts
   multiple-bugzillas
