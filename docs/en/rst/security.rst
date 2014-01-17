

.. _security:

=================
Bugzilla Security
=================

While some of the items in this chapter are related to the operating
system Bugzilla is running on or some of the support software required to
run Bugzilla, it is all related to protecting your data. This is not
intended to be a comprehensive guide to securing Linux, Apache, MySQL, or
any other piece of software mentioned. There is no substitute for active
administration and monitoring of a machine. The key to good security is
actually right in the middle of the word: *U R It*.

While programmers in general always strive to write secure code,
accidents can and do happen. The best approach to security is to always
assume that the program you are working with isn't 100% secure and restrict
its access to other parts of your machine as much as possible.

.. _security-os:

Operating System
################

.. _security-os-ports:

TCP/IP Ports
============

.. COMMENT: TODO: Get exact number of ports

The TCP/IP standard defines more than 65,000 ports for sending
and receiving traffic. Of those, Bugzilla needs exactly one to operate
(different configurations and options may require up to 3). You should
audit your server and make sure that you aren't listening on any ports
you don't need to be. It's also highly recommended that the server
Bugzilla resides on, along with any other machines you administer, be
placed behind some kind of firewall.

.. _security-os-accounts:

System User Accounts
====================

Many daemons, such
as Apache's :file:`httpd` or MySQL's
:file:`mysqld`, run as either ``root`` or
``nobody``. This is even worse on Windows machines where the
majority of services
run as ``SYSTEM``. While running as ``root`` or
``SYSTEM`` introduces obvious security concerns, the
problems introduced by running everything as ``nobody`` may
not be so obvious. Basically, if you run every daemon as
``nobody`` and one of them gets compromised it can
compromise every other daemon running as ``nobody`` on your
machine. For this reason, it is recommended that you create a user
account for each daemon.

.. note:: You will need to set the ``webservergroup`` option
   in :file:`localconfig` to the group your web server runs
   as. This will allow :file:`./checksetup.pl` to set file
   permissions on Unix systems so that nothing is world-writable.

.. _security-os-chroot:

The :file:`chroot` Jail
=======================

If your system supports it, you may wish to consider running
Bugzilla inside of a :file:`chroot` jail. This option
provides unprecedented security by restricting anything running
inside the jail from accessing any information outside of it. If you
wish to use this option, please consult the documentation that came
with your system.

.. _security-webserver:

Web server
##########

.. _security-webserver-access:

Disabling Remote Access to Bugzilla Configuration Files
=======================================================

There are many files that are placed in the Bugzilla directory
area that should not be accessible from the web server. Because of the way
Bugzilla is currently layed out, the list of what should and should not
be accessible is rather complicated. A quick way is to run
:file:`testserver.pl` to check if your web server serves
Bugzilla files as expected. If not, you may want to follow the few
steps below.

.. tip:: Bugzilla ships with the ability to create :file:`.htaccess`
   files that enforce these rules. Instructions for enabling these
   directives in Apache can be found in :ref:`http-apache`

- In the main Bugzilla directory, you should:
  - Block: :file:`*.pl`, :file:`*localconfig*`

- In :file:`data`:
  - Block everything

- In :file:`data/webdot`:

  - If you use a remote webdot server:

    - Block everything
    - But allow :file:`*.dot`
      only for the remote webdot server
  - Otherwise, if you use a local GraphViz:

    - Block everything
    - But allow: :file:`*.png`, :file:`*.gif`, :file:`*.jpg`, :file:`*.map`
  - And if you don't use any dot:

    - Block everything

- In :file:`Bugzilla`:
  - Block everything

- In :file:`template`:
  - Block everything

Be sure to test that data that should not be accessed remotely is
properly blocked. Of particular interest is the localconfig file which
contains your database password. Also, be aware that many editors
create temporary and backup files in the working directory and that
those should also not be accessible. For more information, see
`bug 186383 <http://bugzilla.mozilla.org/show_bug.cgi?id=186383>`_
or
`Bugtraq ID 6501 <http://online.securityfocus.com/bid/6501>`_.
To test, simply run :file:`testserver.pl`, as said above.

.. tip:: Be sure to check :ref:`http` for instructions
   specific to the web server you use.

.. _security-bugzilla:

Bugzilla
########

.. _security-bugzilla-charset:

Prevent users injecting malicious Javascript
============================================

If you installed Bugzilla version 2.22 or later from scratch,
then the *utf8* parameter is switched on by default.
This makes Bugzilla explicitly set the character encoding, following
`a
CERT advisory <http://www.cert.org/tech_tips/malicious_code_mitigation.html#3>`_ recommending exactly this.
The following therefore does not apply to you; just keep
*utf8* turned on.

If you've upgraded from an older version, then it may be possible
for a Bugzilla user to take advantage of character set encoding
ambiguities to inject HTML into Bugzilla comments.
This could include malicious scripts.
This is because due to internationalization concerns, we are unable to
turn the *utf8* parameter on by default for upgraded
installations.
Turning it on manually will prevent this problem.


