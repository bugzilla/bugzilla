.. _apache-windows:

Apache
######

These instructions require editing the Apache configuration file, which is
at :file:`C:\\Program Files\\Apache Group\\Apache2\\conf\\httpd.conf`.

Installing
==========

Download the Apache HTTP Server, version 2.2.x or higher, from
`the Apache website <http://httpd.apache.org/download.cgi>`_.

Apache uses a standard Windows installer. Just follow the prompts, making sure
you "Install for All Users". Be aware the Apache will always install itself
into an :file:`Apache2` directory under what ever path you specify. The
default install path will be displayed as
:file:`C:\\Program Files\\Apache Group`, which will result in Apache being
installed to :file:`C:\\Program Files\\Apache Group\\Apache2`.

If you are already running IIS on your machine, you must configure Apache to
run on a port other than 80, which IIS is using. However you aren't asked the
port to listen on at install time. Choose "All Users" (which says port 80),
and we'll change the port later.

The remainder of this document assumes you have installed Apache into
the default location, :file:`C:\\Program Files\\Apache Group\\Apache2`.

Apache Account Permissions
==========================

By default Apache installs itself to run as the SYSTEM account. For security
reasons it's better the reconfigure the service to run as an Apache user.
Create a new Windows user that is a member of **no** groups, and reconfigure
the Apache2 service to run as that account.

Whichever account you are running Apache as, SYSTEM or otherwise, needs write
and modify access to the following directories and all their subdirectories.
Depending on your version of Windows, this access may already be granted.

* :file:`C:\\Bugzilla\\data`
* :file:`C:\\Program Files\\Apache Group\\Apache2\\logs`
* :file:`C:\\Temp`
* :file:`C:\\Windows\\Temp`

Note that :file:`C:\\Bugzilla\\data` is created the first time you run
:file:`checksetup.pl`.

Port and DocumentRoot
=====================

Edit the Apache configuration file (see above).

If you need to change the port that Apache runs on (listens on, or binds to),
for example because another web server such as IIS is running on the same
machine, edit the ``Listen`` option and change the value after the colon.

Change the ``DocumentRoot`` setting to point to :file:`C:/Bugzilla`. There
are two locations in :file:`httpd.conf` that need to be updated (search for
``DocumentRoot``). You need to use ``/`` instead of ``\`` as a path separator.

Enable CGI Support
==================

Edit the Apache configuration file (see above).

To enable CGI support in Apache, you need to enable the CGI handler, by
uncommenting the ``AddHandler cgi-script .cgi`` line.

Teach Apache About Bugzilla
===========================

Edit the Apache configuration file (see above).

Add the following stanza:

.. code-block:: apache

   <Directory "C:/Bugzilla">
       ScriptInterpreterSource Registry-Strict
       Options +ExecCGI +FollowSymLinks
       DirectoryIndex index.cgi index.html
       AllowOverride Limit FileInfo Indexes Options
   </Directory>

In order for ``ScriptInterpreterSource Registry-Strict`` to work, you also
need to add an entry to the Registry so Apache will use Perl to execute .cgi
files.

Create a key ``HKEY_CLASSES_ROOT\.cgi\Shell\ExecCGI\Command`` with the
default value of the full path of :file:`perl.exe` with a ``-T`` parameter.
For example :file:`C:\\Perl\\bin\\perl.exe -T`.

Logging
=======

Unless you want to keep statistics on how many hits your Bugzilla install is
getting, it's a good idea to disable logging by commenting out the
``CustomLog`` directive in the Apache config file.

If you don't disable logging, you should at least disable logging of "query
strings". When external systems interact with Bugzilla via webservices
(REST/XMLRPC/JSONRPC) they include the user's credentials as part of the URL
(in the query string). Therefore, to avoid storing passwords in clear text
on the server we recommend configuring Apache to not include the query string
in its log files.

#. Find the following line in the Apache config file, which defines the
   logging format for ``vhost_combined``:

   .. code-block:: apache

      LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined

#. Replace ``%r`` with ``%m %U``.

(If you have configured Apache differently, a different log line might apply.
Adjust these instructions accordingly.)

Restart Apache
==============

Finally, restart Apache to get it pick up the changes:

:command:`net stop apache2`

:command:`net start apache2`
