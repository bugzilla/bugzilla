.. _finding:

Finding Bugs
############

Bugzilla has a number of different search options.

.. note:: Bugzilla queries are case-insensitive and accent-insensitive when
    used with either MySQL or Oracle databases. When using Bugzilla with
    PostgreSQL, however, some queries are case sensitive. This is due to
    the way PostgreSQL handles case and accent sensitivity.

.. _quicksearch:

Quicksearch
===========

Quicksearch is a single-text-box query tool. You'll find it in
Bugzilla's header or footer.

Quicksearch uses
metacharacters to indicate what is to be searched. For example, typing

  ``foo|bar``

into Quicksearch would search for "foo" or "bar" in the
summary and status whiteboard of a bug; adding

  ``:BazProduct``

would search only in that product.

You can also use it to go directly to a bug by entering its number or its
alias.

.. todo:: Need to incorporate the full reference, and link it properly from
          the GUI. https://bugzilla.mozilla.org/page.cgi?id=quicksearch.html
          Turn this item into a bug after checkin.

Simple Search
=============

Simple Search is good for finding one particular bug. It works like internet
search engines - just enter some keywords and off you go.

Advanced Search
===============

The Advanced Search page is used to produce a list of all bugs fitting
exact criteria. `You can play with it on
Landfill <http://landfill.bugzilla.org/bugzilla-tip/query.cgi?format=advanced>`_.

Advanced Search has controls for selecting different possible
values for all of the fields in a bug, as described above. For some
fields, multiple values can be selected. In those cases, Bugzilla
returns bugs where the content of the field matches any one of the selected
values. If none is selected, then the field can take any value.

After a search is run, you can save it as a Saved Search, which
will appear in the page footer. If you are in the group defined
by the "querysharegroup" parameter, you may share your queries
with other users; see :ref:`saved-searches` for more details.

.. _custom-search:

Custom Search
=============

Highly advanced querying is done using the Custom Search feature of the
Advanced Search page.

The search criteria here further restrict the set of results
returned by a query over and above those defined in the fields at the top
of the page. It is thereby possible to search for bugs
based on elaborate combinations of criteria.

The simplest boolean searches have only one term. These searches
permit the selected *field*
to be compared using a
selectable *operator* to a
specified *value.* Much of this could be reproduced using the standard
fields. However, you can then combine terms using "Match ANY" or "Match ALL",
using parentheses for combining and priority, in order to construct searches
of almost arbitrary complexity.

There are three fields in each row of a boolean search.

- *Field:*
  the items being searched

- *Operator:*
  the comparison operator

- *Value:*
  the value to which the field is being compared

.. _negation:

.. _multiplecharts:

Multiple Charts
---------------

.. todo:: This needs rewriting for the new UI.
          Turn this item into a bug after checkin.
          
The terms within a single row of a boolean chart are all
constraints on a single piece of data. If you are looking for
a bug that has two different people cc'd on it, then you need
to use two boolean charts. A search for

    ("cc" "contains the string" "foo@") AND
    ("cc" "contains the string" "@mozilla.org")

would return only bugs with "foo@mozilla.org" on the cc list.
If you wanted bugs where there is someone on the cc list
containing "foo@" and someone else containing "@mozilla.org",
then you would need two boolean charts.

    First chart: ("cc" "contains the string" "foo@")
    Second chart: ("cc" "contains the string" "@mozilla.org")

The bugs listed will be only the bugs where ALL the charts are true.

Negation
--------

At first glance, negation seems redundant. Rather than
searching for

    NOT("summary" "contains the string" "foo"),

one could search for

    ("summary" "does not contain the string" "foo").

However, the search

    ("CC" "does not contain the string" "@mozilla.org")

would find every bug where anyone on the CC list did not contain
"@mozilla.org" while

    NOT("CC" "contains the string" "@mozilla.org")

would find every bug where there was nobody on the CC list who
did contain the string. Similarly, the use of negation also permits
complex expressions to be built using terms OR'd together and then
negated. Negation permits queries such as

    NOT(("product" "equals" "update") OR
    ("component" "equals" "Documentation"))

to find bugs that are neither
in the update product or in the documentation component or

    NOT(("commenter" "equals" "%assignee%") OR
    ("component" "equals" "Documentation"))

to find non-documentation
bugs on which the assignee has never commented.

.. _pronouns:

Pronoun Substitution
--------------------

Sometimes, a query needs to compare a user-related field
(such as Reporter) with a role-specific user (such as the
user running the query or the user to whom each bug is assigned). For
example, you may want to find all bugs which are assigned to the person
who reported them.

When the Custom Search operator is either "equals" or "notequals", the value
can be "%reporter%", "%assignee%", "%qacontact%", or "%user%".
The user pronoun
refers to the user who is executing the query or, in the case
of whining reports, the user who will be the recipient
of the report. The reporter, assignee, and qacontact
pronouns refer to the corresponding fields in the bug.

Boolean charts also let you type a group name in any user-related
field if the operator is either "equals", "notequals" or "anyexact".
This will let you query for any member belonging (or not) to the
specified group. The group name must be entered following the
"%group.foo%" syntax, where "foo" is the group name.
So if you are looking for bugs reported by any user being in the
"editbugs" group, then you can type "%group.editbugs%".

.. _list:

Bug Lists
=========

The result of a search is a list of matching bugs.

The format of the list is configurable. For example, it can be
sorted by clicking the column headings. Other useful features can be
accessed using the links at the bottom of the list:

Long Format:
    this gives you a large page with a non-editable summary of the fields
    of each bug.

XML:
    get the buglist in the XML format.

CSV:
    get the buglist as comma-separated values, for import into e.g.
    a spreadsheet.

Feed:
    get the buglist as an Atom feed.  Copy this link into your
    favorite feed reader.  If you are using Firefox, you can also
    save the list as a live bookmark by clicking the live bookmark
    icon in the status bar.  To limit the number of bugs in the feed,
    add a limit=n parameter to the URL.

iCalendar:
    Get the buglist as an iCalendar file. Each bug is represented as a
    to-do item in the imported calendar.

Change Columns:
    change the bug attributes which appear in the list.

Change several bugs at once:
    If your account is sufficiently empowered, and more than one bug
    appears in the bug list, this link is displayed and lets you easily make
    the same change to all the bugs in the list - for example, changing
    their assignee.

Send mail to bug assignees:  
    If more than one bug appear in the bug list and there are at least
    two distinct bug assignees, this links is displayed which lets you
    easily send a mail to the assignees of all bugs on the list.

Edit Search:
    If you didn't get exactly the results you were looking for, you can
    return to the Query page through this link and make small revisions
    to the query you just made so you get more accurate results.

Remember Search As:
    You can give a search a name and remember it; a link will appear
    in your page footer giving you quick access to run it again later.

.. _individual-buglists:

Adding and Removing Tags on Bugs
================================

.. todo:: Looks like you can no longer do this from search results; is that right?
          Turn this item into a bug after checkin.
          
You can add and remove tags from individual bugs, which let you find and
manage bugs more easily. Tags are per-user and so are only visible and editable
by the user who created them. You can then run queries using tags as a criteria,
either by using the Advanced Search form, or simply by typing "tag\:my_tag_name"
in the QuickSearch box at the top (or bottom) of the page. Tags can also be
displayed in buglists.

This feature is useful when you want to keep track of several bugs, but
for different reasons. Instead of adding yourself to the CC list of all
these bugs and mixing all these reasons, you can now store these bugs in
separate lists, e.g. ``Keep in mind``, ``Interesting bugs``,
or ``Triage``. One big advantage of this way to manage bugs
is that you can easily add or remove tags from bugs one by one.
