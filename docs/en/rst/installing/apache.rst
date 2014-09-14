.. _http-apache:

Apache
######

You have two options for running Bugzilla under Apache - mod_cgi (the
default) and mod_perl. mod_perl is faster but takes more resources. You
should probably only consider mod_perl if your Bugzilla is going to be heavily
used.

.. _http-apache-mod_cgi:

Apache with mod_cgi
===================

To configure your Apache web server to work with Bugzilla while using
mod_cgi, do the following:

#. Load :file:`httpd.conf` in your editor.
   In Fedora and Red Hat Linux, this file is found in
   :file:`/etc/httpd/conf`.

#. Apache uses ``<Directory>``
   directives to permit fine-grained permission setting. Add the
   following lines to a directive that applies to the location
   of your Bugzilla installation. (If such a section does not
   exist, you'll want to add one.) In this example, Bugzilla has
   been installed at :file:`/var/www/html/bugzilla`.

.. code-block:: apache

       <Directory /var/www/html/bugzilla>
         AddHandler cgi-script .cgi
         Options +ExecCGI +FollowSymLinks
         DirectoryIndex index.cgi index.html
         AllowOverride Limit FileInfo Indexes Options
       </Directory>

These instructions allow Apache to run .cgi files found
within the Bugzilla directory; instructs the server to look
for a file called :file:`index.cgi` or, if not
found, :file:`index.html` if someone
only types the directory name into the browser; and allows
Bugzilla's :file:`.htaccess` files to override
some global permissions.

.. note:: On Windows, you may have to also add the
   ``ScriptInterpreterSource Registry-Strict``
   line, see :ref:`Windows specific notes <win32-http>`.

   XXX Does this link still work?

.. _http-apache-mod_perl:

Apache with mod_perl
====================

Bugzilla requires version 1.999022 (AKA 2.0.0-RC5) of mod_perl.

XXX Is this relevant any more - how old is that version?

XXX Can one use mod_perl on Windows?

Some configuration is required to make Bugzilla work with Apache
and mod_perl.

#. Load :file:`httpd.conf` in your editor.
   In Fedora and Red Hat Linux, this file is found in :file:`/etc/httpd/conf`.

#. Add the following information to your httpd.conf file, substituting
   where appropriate with your own local paths.

   .. code-block:: apache

       PerlSwitches -w -T
       PerlConfigRequire /var/www/html/bugzilla/mod_perl.pl

   .. note:: This should be used instead of the <Directory> block
      shown above. This should also be above any other ``mod_perl``
      directives within the :file:`httpd.conf` and the directives must be
      specified in the order above.

   .. warning:: You should also ensure that you have disabled ``KeepAlive``
      support in your Apache install when utilizing Bugzilla under mod_perl

      XXX How?

On restarting Apache, Bugzilla should now be running within the
mod_perl environment.

Please bear the following points in mind when considering using Bugzilla
under mod_perl:

- mod_perl support in Bugzilla can take up a HUGE amount of RAM - easily
  30MB per httpd child. The more RAM you can get, the better. mod_perl is
  basically trading RAM for speed. At least 2GB total system RAM is
  recommended for running Bugzilla under mod_perl.
  
- Under mod_perl, you have to restart Apache if you make any manual change to
  any Bugzilla file. You can't just reload--you have to actually
  *restart* the server (as in make sure it stops and starts
  again). You *can* change :file:`localconfig` and the :file:`params` file
  manually, if you want, because those are re-read every time you load a page.

- You must run in Apache's Prefork MPM (this is the default). The Worker MPM
  may not work -- we haven't tested Bugzilla's mod_perl support under threads.
  (And, in fact, we're fairly sure it *won't* work.)

- Bugzilla generally expects to be the only mod_perl application running on
  your entire server. It may or may not work if there are other applications also
  running under mod_perl. It does try its best to play nice with other mod_perl
  applications, but it still may have conflicts.

- It is recommended that you have one Bugzilla instance running under mod_perl
  on your server. Bugzilla has not been tested with more than one instance running.
