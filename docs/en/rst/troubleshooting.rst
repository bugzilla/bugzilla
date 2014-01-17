

.. _troubleshooting:

===============
Troubleshooting
===============

This section gives solutions to common Bugzilla installation
problems. If none of the section headings seems to match your
problem, read the general advice.

.. _general-advice:

General Advice
##############

If you can't get :file:`checksetup.pl` to run to
completion, it normally explains what's wrong and how to fix it.
If you can't work it out, or if it's being uncommunicative, post
the errors in the
`mozilla.support.bugzilla <news://news.mozilla.org/mozilla.support.bugzilla>`_
newsgroup.

If you have made it all the way through
:ref:`installation` (Installation) and
:ref:`configuration` (Configuration) but accessing the Bugzilla
URL doesn't work, the first thing to do is to check your web server error
log. For Apache, this is often located at
:file:`/etc/logs/httpd/error_log`. The error messages
you see may be self-explanatory enough to enable you to diagnose and
fix the problem. If not, see below for some commonly-encountered
errors. If that doesn't help, post the errors to the newsgroup.

Bugzilla can also log all user-based errors (and many code-based errors)
that occur, without polluting the web server's error log.  To enable
Bugzilla error logging, create a file that Bugzilla can write to, named
:file:`errorlog`, in the Bugzilla :file:`data`
directory.  Errors will be logged as they occur, and will include the type
of the error, the IP address and username (if available) of the user who
triggered the error, and the values of all environment variables; if a
form was being submitted, the data in the form will also be included.
To disable error logging, delete or rename the
:file:`errorlog` file.

.. _trbl-testserver:

The Apache web server is not serving Bugzilla pages
###################################################

After you have run :command:`checksetup.pl` twice,
run :command:`testserver.pl http://yoursite.yourdomain/yoururl`
to confirm that your web server is configured properly for
Bugzilla.

::

    bash$ ./testserver.pl http://landfill.bugzilla.org/bugzilla-tip
    TEST-OK Webserver is running under group id in $webservergroup.
    TEST-OK Got ant picture.
    TEST-OK Webserver is executing CGIs.
    TEST-OK Webserver is preventing fetch of http://landfill.bugzilla.org/bugzilla-tip/localconfig.

.. _trbl-perlmodule:

I installed a Perl module, but :file:`checksetup.pl` claims it's not installed!
###############################################################################

This could be caused by one of two things:

#. You have two versions of Perl on your machine. You are installing
   modules into one, and Bugzilla is using the other. Rerun the CPAN
   commands (or manual compile) using the full path to Perl from the
   top of :file:`checksetup.pl`. This will make sure you
   are installing the modules in the right place.

#. The permissions on your library directories are set incorrectly.
   They must, at the very least, be readable by the web server user or
   group. It is recommended that they be world readable.

.. _trbl-dbdSponge:

DBD::Sponge::db prepare failed
##############################

The following error message may appear due to a bug in DBD::mysql
(over which the Bugzilla team have no control):

::

    DBD::Sponge::db prepare failed: Cannot determine NUM_OF_FIELDS at D:/Perl/site/lib/DBD/mysql.pm line 248.
    SV = NULL(0x0) at 0x20fc444
    REFCNT = 1
    FLAGS = (PADBUSY,PADMY)

To fix this, go to
:file:`<path-to-perl>/lib/DBD/sponge.pm`
in your Perl installation and replace

::

    my $numFields;
    if ($attribs->{'NUM_OF_FIELDS'}) {
    $numFields = $attribs->{'NUM_OF_FIELDS'};
    } elsif ($attribs->{'NAME'}) {
    $numFields = @{$attribs->{NAME}};

with

::

    my $numFields;
    if ($attribs->{'NUM_OF_FIELDS'}) {
    $numFields = $attribs->{'NUM_OF_FIELDS'};
    } elsif ($attribs->{'NAMES'}) {
    $numFields = @{$attribs->{NAMES}};

(note the S added to NAME.)

.. _paranoid-security:

cannot chdir(/var/spool/mqueue)
###############################

If you are installing Bugzilla on SuSE Linux, or some other
distributions with ``paranoid`` security options, it is
possible that the checksetup.pl script may fail with the error:
::

    cannot chdir(/var/spool/mqueue): Permission denied

This is because your :file:`/var/spool/mqueue`
directory has a mode of ``drwx------``.
Type :command:`chmod 755 :file:`/var/spool/mqueue``
as root to fix this problem. This will allow any process running on your
machine the ability to *read* the
:file:`/var/spool/mqueue` directory.

.. _trbl-relogin-everyone:

Everybody is constantly being forced to relogin
###############################################

The most-likely cause is that the ``cookiepath`` parameter
is not set correctly in the Bugzilla configuration.  You can change this (if
you're a Bugzilla administrator) from the editparams.cgi page via the web interface.

The value of the cookiepath parameter should be the actual directory
containing your Bugzilla installation, *as seen by the end-user's
web browser*. Leading and trailing slashes are mandatory. You can
also set the cookiepath to any directory which is a parent of the Bugzilla
directory (such as '/', the root directory). But you can't put something
that isn't at least a partial match or it won't work. What you're actually
doing is restricting the end-user's browser to sending the cookies back only
to that directory.

How do you know if you want your specific Bugzilla directory or the
whole site?

If you have only one Bugzilla running on the server, and you don't
mind having other applications on the same server with it being able to see
the cookies (you might be doing this on purpose if you have other things on
your site that share authentication with Bugzilla), then you'll want to have
the cookiepath set to "/", or to a sufficiently-high enough directory that
all of the involved apps can see the cookies.

.. _trbl-relogin-everyone-share:

Examples of urlbase/cookiepath pairs for sharing login cookies
==============================================================

|    urlbase is http://bugzilla.mozilla.org/
|    cookiepath is /


|    urlbase is http://tools.mysite.tld/bugzilla/
|    but you have http://tools.mysite.tld/someotherapp/ which shares
|    authentication with your Bugzilla
|
|    cookiepath is /

On the other hand, if you have more than one Bugzilla running on the
server (some people do - we do on landfill) then you need to have the
cookiepath restricted enough so that the different Bugzillas don't
confuse their cookies with one another.

.. _trbl-relogin-everyone-restrict:

Examples of urlbase/cookiepath pairs to restrict the login cookie
=================================================================

|    urlbase is http://landfill.bugzilla.org/bugzilla-tip/
|    cookiepath is /bugzilla-tip/

|    urlbase is http://landfill.bugzilla.org/bugzilla-4.0-branch/
|    cookiepath is /bugzilla-4.0-branch/

If you had cookiepath set to ``/`` at any point in the
past and need to set it to something more restrictive
(i.e. ``/bugzilla/``), you can safely do this without
requiring users to delete their Bugzilla-related cookies in their
browser (this is true starting with Bugzilla 2.18 and Bugzilla 2.16.5).

.. _trbl-index:

:file:`index.cgi` doesn't show up unless specified in the URL
#############################################################

You probably need to set up your web server in such a way that it
will serve the index.cgi page as an index page.

If you are using Apache, you can do this by adding
:file:`index.cgi` to the end of the
``DirectoryIndex`` line
as mentioned in :ref:`http-apache`.

.. _trbl-passwd-encryption:

checksetup.pl reports "Client does not support authentication protocol requested by server..."
##############################################################################################

This error is occurring because you are using the new password
encryption that comes with MySQL 4.1, while your
:file:`DBD::mysql` module was compiled against an
older version of MySQL. If you recompile :file:`DBD::mysql`
against the current MySQL libraries (or just obtain a newer version
of this module) then the error may go away.

If that does not fix the problem, or if you cannot recompile the
existing module (e.g. you're running Windows) and/or don't want to
replace it (e.g. you want to keep using a packaged version), then a
workaround is available from the MySQL docs:
`<http://dev.mysql.com/doc/mysql/en/Old_client.html>`_


