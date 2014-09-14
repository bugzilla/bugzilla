.. _cust-change-permissions:

Who Can Change What
###################

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

Because this kind of change is such a common request, we have added a
specific hook for it that :ref:`extensions` can call. It's called
``bug_check_can_change_field``, and it's documented `in the Hooks
documentation <http://www.bugzilla.org/docs/tip/en/html/api/Bugzilla/Hook.html#bug_check_can_change_field>`_.
