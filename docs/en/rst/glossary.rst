

.. _glossary:

========
Glossary
========

0-9, high ascii
###############

.htaccess
    Apache web server, and other NCSA-compliant web servers,
    observe the convention of using files in directories called
    :file:`.htaccess`
    to restrict access to certain files. In Bugzilla, they are used
    to keep secret files which would otherwise
    compromise your installation - e.g. the
    :file:`localconfig`
    file contains the password to your database.
    curious.

.. _gloss-a:

A
#

Apache
    In this context, Apache is the web server most commonly used
    for serving up Bugzilla
    pages. Contrary to popular belief, the apache web server has nothing
    to do with the ancient and noble Native American tribe, but instead
    derived its name from the fact that it was
    ``a patchy``
    version of the original
    NCSA
    world-wide-web server.

    Useful Directives when configuring Bugzilla

    `AddHandler <http://httpd.apache.org/docs/2.0/mod/mod_mime.html#addhandler>`_
        Tell Apache that it's OK to run CGI scripts.

    `AllowOverride <http://httpd.apache.org/docs-2.0/mod/core.html#allowoverride>`_, `Options <http://httpd.apache.org/docs-2.0/mod/core.html#options>`_
        These directives are used to tell Apache many things about
        the directory they apply to. For Bugzilla's purposes, we need
        them to allow script execution and :file:`.htaccess`
        overrides.

    `DirectoryIndex <http://httpd.apache.org/docs-2.0/mod/mod_dir.html#directoryindex>`_
        Used to tell Apache what files are indexes. If you can
        not add :file:`index.cgi` to the list of valid files,
        you'll need to set ``$index_html`` to
        1 in :file:`localconfig` so
        :command:`./checksetup.pl` will create an
        :file:`index.html` that redirects to
        :file:`index.cgi`.

    `ScriptInterpreterSource <http://httpd.apache.org/docs-2.0/mod/core.html#scriptinterpretersource>`_
        Used when running Apache on windows so the shebang line
        doesn't have to be changed in every Bugzilla script.

    For more information about how to configure Apache for Bugzilla,
    see :ref:`http-apache`.

.. _gloss-b:

B
#

Bug
    A
    ``bug``
    in Bugzilla refers to an issue entered into the database which has an
    associated number, assignments, comments, etc. Some also refer to a
    ``tickets``
    or
    ``issues``;
    in the context of Bugzilla, they are synonymous.

Bug Number
    Each Bugzilla bug is assigned a number that uniquely identifies
    that bug. The bug associated with a bug number can be pulled up via a
    query, or easily from the very front page by typing the number in the
    "Find" box.

Bugzilla
    Bugzilla is the world-leading free software bug tracking system.

.. _gloss-c:

C
#

Common Gateway Interface (CGI)
    CGI is an acronym for Common Gateway Interface. This is
    a standard for interfacing an external application with a web server. Bugzilla
    is an example of a CGI application.

Component
    A Component is a subsection of a Product. It should be a narrow
    category, tailored to your organization. All Products must contain at
    least one Component (and, as a matter of fact, creating a Product
    with no Components will create an error in Bugzilla).

Comprehensive Perl Archive Network (CPAN)
    CPAN
    stands for the
    ``Comprehensive Perl Archive Network``.
    CPAN maintains a large number of extremely useful
    Perl
    modules - encapsulated chunks of code for performing a
    particular task.

    The :file:`contrib` directory is
    a location to put scripts that have been contributed to Bugzilla but
    are not a part of the official distribution. These scripts are written
    by third parties and may be in languages other than perl. For those
    that are in perl, there may be additional modules or other requirements
    than those of the official distribution.

    .. note:: Scripts in the :file:`contrib`
       directory are not officially supported by the Bugzilla team and may
       break in between versions.

.. _gloss-d:

D
#

daemon
    A daemon is a computer program which runs in the background. In
    general, most daemons are started at boot time via System V init
    scripts, or through RC scripts on BSD-based systems.
    mysqld,
    the MySQL server, and
    apache,
    a web server, are generally run as daemons.

DOS Attack
    A DOS, or Denial of Service attack, is when a user attempts to
    deny access to a web server by repeatedly accessing a page or sending
    malformed requests to a webserver. A D-DOS, or
    Distributed Denial of Service attack, is when these requests come
    from multiple sources at the same time. Unfortunately, these are much
    more difficult to defend against.

.. _gloss-g:

G
#

Groups
    The word
    ``Groups``
    has a very special meaning to Bugzilla. Bugzilla's main security
    mechanism comes by placing users in groups, and assigning those
    groups certain privileges to view bugs in particular
    Products
    in the
    Bugzilla
    database.

.. _gloss-j:

J
#

JavaScript
    JavaScript is cool, we should talk about it.

.. _gloss-m:

M
#

Message Transport Agent (MTA)
    A Message Transport Agent is used to control the flow of email on a system.
    The `Email::Send <http://search.cpan.org/dist/Email-Send/lib/Email/Send.pm>`_
    Perl module, which Bugzilla uses to send email, can be configured to
    use many different underlying implementations for actually sending the
    mail using the ``mail_delivery_method`` parameter.

MySQL
    MySQL is one of the supported
    RDBMS for Bugzilla. MySQL
    can be downloaded from `<http://www.mysql.com>`_. While you
    should familiarize yourself with all of the documentation, some high
    points are:

    `Backup <http://www.mysql.com/doc/en/Backup.html>`_
        Methods for backing up your Bugzilla database.
    `Option Files <http://www.mysql.com/doc/en/Option_files.html>`_
        Information about how to configure MySQL using
        :file:`my.cnf`.
    `Privilege System <http://www.mysql.com/doc/en/Privilege_system.html>`_
        Information about how to protect your MySQL server.

.. _gloss-p:

P
#

Perl Package Manager (PPM)
    `<http://aspn.activestate.com/ASPN/Downloads/ActivePerl/PPM/>`_

Product
    A Product is a broad category of types of bugs, normally
    representing a single piece of software or entity. In general,
    there are several Components to a Product. A Product may define a
    group (used for security) for all bugs entered into
    its Components.

Perl
    First written by Larry Wall, Perl is a remarkable program
    language. It has the benefits of the flexibility of an interpreted
    scripting language (such as shell script), combined with the speed
    and power of a compiled language, such as C.
    Bugzilla
    is maintained in Perl.

.. _gloss-q:

Q
#

QA
    ``QA``,
    ``Q/A``, and
    ``Q.A.``
    are short for
    ``Quality Assurance``.
    In most large software development organizations, there is a team
    devoted to ensuring the product meets minimum standards before
    shipping. This team will also generally want to track the progress of
    bugs over their life cycle, thus the need for the
    ``QA Contact``
    field in a bug.

.. _gloss-r:

R
#

Relational DataBase Management System (RDBMS)
    A relational database management system is a database system
    that stores information in tables that are related to each other.

Regular Expression (regexp)
    A regular expression is an expression used for pattern matching.
    `Documentation <http://perldoc.com/perl5.6/pod/perlre.html#Regular-Expressions>`_

.. _gloss-s:

S
#

Service
    In Windows NT environment, a boot-time background application
    is referred to as a service. These are generally managed through the
    control panel while logged in as an account with
    ``Administrator`` level capabilities. For more
    information, consult your Windows manual or the MSKB.

    SGML
    stands for
    ``Standard Generalized Markup Language``.
    Created in the 1980's to provide an extensible means to maintain
    documentation based upon content instead of presentation,
    SGML
    has withstood the test of time as a robust, powerful language.
    XML
    is the
    ``baby brother``
    of SGML; any valid
    XML
    document it, by definition, a valid
    SGML
    document. The document you are reading is written and maintained in
    SGML,
    and is also valid
    XML
    if you modify the Document Type Definition.

.. _gloss-t:

T
#

Target Milestone
    Target Milestones are Product goals. They are configurable on a
    per-Product basis. Most software development houses have a concept of
    ``milestones``
    where the people funding a project expect certain functionality on
    certain dates. Bugzilla facilitates meeting these milestones by
    giving you the ability to declare by which milestone a bug will be
    fixed, or an enhancement will be implemented.

Tool Command Language (TCL)
    TCL is an open source scripting language available for Windows,
    Macintosh, and Unix based systems. Bugzilla 1.0 was written in TCL but
    never released. The first release of Bugzilla was 2.0, which was when
    it was ported to perl.

.. _gloss-z:

Z
#

Zarro Boogs Found
    This is just a goofy way of saying that there were no bugs
    found matching your query. When asked to explain this message,
    Terry had the following to say:

        *Terry Weissman*:
        I've been asked to explain this ... way back when, when
        Netscape released version 4.0 of its browser, we had a release
        party.  Naturally, there had been a big push to try and fix every
        known bug before the release. Naturally, that hadn't actually
        happened.  (This is not unique to Netscape or to 4.0; the same thing
        has happened with every software project I've ever seen.)  Anyway,
        at the release party, T-shirts were handed out that said something
        like "Netscape 4.0: Zarro Boogs". Just like the software, the
        T-shirt had no known bugs.  Uh-huh.
        So, when you query for a list of bugs, and it gets no results,
        you can think of this as a friendly reminder.  Of \*course* there are
        bugs matching your query, they just aren't in the bugsystem yet...

