

.. _patches:

=======
Contrib
=======

There are a number of unofficial Bugzilla add-ons in the
:file:`$BUGZILLA_ROOT/contrib/`
directory. This section documents them.

.. _cmdline:

Command-line Search Interface
#############################

There are a suite of Unix utilities for searching Bugzilla from the
command line. They live in the
:file:`contrib/cmdline` directory.
There are three files - :file:`query.conf`,
:file:`buglist` and :file:`bugs`.

.. warning:: These files pre-date the templatization work done as part of the
   2.16 release, and have not been updated.

:file:`query.conf` contains the mapping from
options to field names and comparison types. Quoted option names
are ``grepped`` for, so it should be easy to edit this
file. Comments (#) have no effect; you must make sure these lines
do not contain any quoted ``option``.

:file:`buglist` is a shell script that submits a
Bugzilla query and writes the resulting HTML page to stdout.
It supports both short options, (such as ``-Afoo``
or ``-Rbar``) and long options (such
as ``--assignedto=foo`` or ``--reporter=bar``).
If the first character of an option is not ``-``, it is
treated as if it were prefixed with ``--default=``.

The column list is taken from the COLUMNLIST environment variable.
This is equivalent to the ``Change Columns`` option
that is available when you list bugs in buglist.cgi. If you have
already used Bugzilla, grep for COLUMNLIST in your cookies file
to see your current COLUMNLIST setting.

:file:`bugs` is a simple shell script which calls
:file:`buglist` and extracts the
bug numbers from the output. Adding the prefix
``http://bugzilla.mozilla.org/buglist.cgi?bug_id=``
turns the bug list into a working link if any bugs are found.
Counting bugs is easy. Pipe the results through
:command:`sed -e 's/,/ /g' | wc | awk '{printf $2 "\\n"}'`

Akkana Peck says she has good results piping
:file:`buglist` output through
:command:`w3m -T text/html -dump`

.. _cmdline-bugmail:

Command-line 'Send Unsent Bug-mail' tool
########################################

Within the :file:`contrib` directory
exists a utility with the descriptive (if compact) name
of :file:`sendunsentbugmail.pl`. The purpose of this
script is, simply, to send out any bug-related mail that should
have been sent by now, but for one reason or another has not.

To accomplish this task, :file:`sendunsentbugmail.pl` uses
the same mechanism as the :file:`sanitycheck.cgi` script;
it scans through the entire database looking for bugs with changes that
were made more than 30 minutes ago, but where there is no record of
anyone related to that bug having been sent mail. Having compiled a list,
it then uses the standard rules to determine who gets mail, and sends it
out.

As the script runs, it indicates the bug for which it is currently
sending mail; when it has finished, it gives a numerical count of how
many mails were sent and how many people were excluded. (Individual
user names are not recorded or displayed.) If the script produces
no output, that means no unsent mail was detected.

*Usage*: move the sendunsentbugmail.pl script
up into the main directory, ensure it has execute permission, and run it
from the command line (or from a cron job) with no parameters.


