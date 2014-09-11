.. _cust-change-permissions:

Who Can Change What
###################

.. warning:: This feature should be considered experimental; the Bugzilla code you
   will be changing is not stable, and could change or move between
   versions. Be aware that if you make modifications as outlined here,
   you may have
   to re-make them or port them if Bugzilla changes internally between
   versions, and you upgrade.

Companies often have rules about which employees, or classes of employees,
are allowed to change certain things in the bug system. For example,
only the bug's designated QA Contact may be allowed to VERIFY the bug.
Bugzilla has been
designed to make it easy for you to write your own custom rules to define
who is allowed to make what sorts of value transition.

By default, assignees, QA owners and users
with *editbugs* privileges can edit all fields of bugs,
except group restrictions (unless they are members of the groups they
are trying to change). Bug reporters also have the ability to edit some
fields, but in a more restrictive manner. Other users, without
*editbugs* privileges, cannot edit
bugs, except to comment and add themselves to the CC list.

For maximum flexibility, customizing this means editing Bugzilla's Perl
code. This gives the administrator complete control over exactly who is
allowed to do what. The relevant method is called
:file:`check_can_change_field()`,
and is found in :file:`Bug.pm` in your
Bugzilla/ directory. If you open that file and search for
``sub check_can_change_field``, you'll find it.

This function has been carefully commented to allow you to see exactly
how it works, and give you an idea of how to make changes to it.
Certain marked sections should not be changed - these are
the ``plumbing`` which makes the rest of the function work.
In between those sections, you'll find snippets of code like:

::

    # Allow the assignee to change anything.
    if ($ownerid eq $whoid) {
        return 1;
    }

It's fairly obvious what this piece of code does.

So, how does one go about changing this function? Well, simple changes
can be made just by removing pieces - for example, if you wanted to
prevent any user adding a comment to a bug, just remove the lines marked
``Allow anyone to change comments.`` If you don't want the
Reporter to have any special rights on bugs they have filed, just
remove the entire section that deals with the Reporter.

More complex customizations are not much harder. Basically, you add
a check in the right place in the function, i.e. after all the variables
you are using have been set up. So, don't look at $ownerid before
$ownerid has been obtained from the database. You can either add a
positive check, which returns 1 (allow) if certain conditions are true,
or a negative check, which returns 0 (deny.) E.g.:

::

    if ($field eq "qacontact") {
        if (Bugzilla->user->in_group("quality_assurance")) {
            return 1;
        }
        else {
            return 0;
        }
    }

This says that only users in the group "quality_assurance" can change
the QA Contact field of a bug.

Getting more weird:

::

    if (($field eq "priority") &&
        (Bugzilla->user->email =~ /.*\\@example\\.com$/))
    {
        if ($oldvalue eq "P1") {
            return 1;
        }
        else {
            return 0;
        }
    }

This says that if the user is trying to change the priority field,
and their email address is @example.com, they can only do so if the
old value of the field was "P1". Not very useful, but illustrative.

.. warning:: If you are modifying :file:`process_bug.cgi` in any
   way, do not change the code that is bounded by DO_NOT_CHANGE blocks.
   Doing so could compromise security, or cause your installation to
   stop working entirely.

For a list of possible field names, look at the bugs table in the
database. If you need help writing custom rules for your organization,
ask in the newsgroup.
