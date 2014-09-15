:orphan:

.. _iis:

Microsoft IIS
#############

If you are running Bugzilla on Windows and choose to use
Microsoft's *Internet Information Services*
or *Personal Web Server* you will need
to perform a number of other configuration steps as explained below.
You may also want to refer to the following Microsoft Knowledge
Base articles:
`245225 - HOW TO: Configure and Test a PERL Script with IIS 4.0,
5.0, and 5.1 <http://support.microsoft.com/default.aspx?scid=kb;en-us;245225>`_
(for *Internet Information Services*) and
`231998 - HOW TO: FP2000: How to Use Perl with Microsoft Personal Web
Server on Windows 95/98 <http://support.microsoft.com/default.aspx?scid=kb;en-us;231998>`_
(for *Personal Web Server*).

You will need to create a virtual directory for the Bugzilla
install.  Put the Bugzilla files in a directory that is named
something *other* than what you want your
end-users accessing.  That is, if you want your users to access
your Bugzilla installation through
``http://<yourdomainname>/Bugzilla``, then do
*not* put your Bugzilla files in a directory
named ``Bugzilla``.  Instead, place them in a different
location, and then use the IIS Administration tool to create a
Virtual Directory named "Bugzilla" that acts as an alias for the
actual location of the files.  When creating that virtual directory,
make sure you add the ``Execute (such as ISAPI applications or
CGI)`` access permission.

You will also need to tell IIS how to handle Bugzilla's
.cgi files. Using the IIS Administration tool again, open up
the properties for the new virtual directory and select the
Configuration option to access the Script Mappings. Create an
entry mapping .cgi to:

::

    <full path to perl.exe >\perl.exe -x<full path to Bugzilla> -wT "%s" %s

For example:

::

    c:\perl\bin\perl.exe -xc:\bugzilla -wT "%s" %s

.. note:: The ActiveState install may have already created an entry for
   .pl files that is limited to ``GET,HEAD,POST``. If
   so, this mapping should be *removed* as
   Bugzilla's .pl files are not designed to be run via a web server.

IIS will also need to know that the index.cgi should be treated
as a default document.  On the Documents tab page of the virtual
directory properties, you need to add index.cgi as a default
document type.  If you  wish, you may remove the other default
document types for this particular virtual directory, since Bugzilla
doesn't use any of them.

Also, and this can't be stressed enough, make sure that files
such as :file:`localconfig` and your
:file:`data` directory are
secured.

XXX See also https://wiki.mozilla.org/Installing_under_IIS_7.5
