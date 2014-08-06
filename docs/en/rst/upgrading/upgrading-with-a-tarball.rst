.. _upgrading-with-a-tarball:

Upgrading with a Tarball
########################

If you are unable (or unwilling) to use Bzr, another option that's
always available is to obtain the latest tarball from the `Download Page <http://www.bugzilla.org/download/>`_ and
create a new Bugzilla installation from that.

This sequence of commands shows how to get the tarball from the
command-line; it is also possible to download it from the site
directly in a web browser. If you go that route, save the file
to the :file:`/var/www/html`
directory (or its equivalent, if you use something else) and
omit the first three lines of the example.

::

    $ cd /var/www/html
    $ wget http://ftp.mozilla.org/pub/mozilla.org/webtools/bugzilla-4.2.1.tar.gz
    ...
    $ tar xzvf bugzilla-4.2.1.tar.gz
    bugzilla-4.2.1/
    bugzilla-4.2.1/colchange.cgi
    ...
    $ cd bugzilla-4.2.1
    $ cp ../bugzilla/localconfig* .
    $ cp -r ../bugzilla/data .
    $ cd ..
    $ mv bugzilla bugzilla.old
    $ mv bugzilla-4.2.1 bugzilla

.. warning:: The :command:`cp` commands both end with periods which
   is a very important detail--it means that the destination
   directory is the current working directory.

.. warning:: If you have some extensions installed, you will have to copy them
   to the new bugzilla directory too. Extensions are located in :file:`bugzilla/extensions/`.
   Only copy those you
   installed, not those managed by the Bugzilla team.

This upgrade method will give you a clean install of Bugzilla.
That's fine if you don't have any local customizations that you
want to maintain. If you do have customizations, then you will
need to reapply them by hand to the appropriate files.
