.. _flags:

Flags
#####

Flags are a way to attach a specific status to a bug or attachment,
either ``+`` or ``-``. The meaning of these symbols depends on the text
the flag itself, but contextually they could mean pass/fail,
accept/reject, approved/denied, or even a simple yes/no. If your site
allows requestable flags, then users may set a flag to ``?`` as a
request to another user that they look at the bug/attachment, and set
the flag to its correct status.

.. _flags-simpleexample:

A Simple Example
================

A developer might want to ask their manager,
``Should we fix this bug before we release version 2.0?``
They might want to do this for a *lot* of bugs,
so it would be nice to streamline the process...

In Bugzilla, it would work this way:

#. The Bugzilla administrator creates a flag type called
   ``blocking2.0`` that shows up on all bugs in
   your product.
   It shows up on the ``Show Bug`` screen
   as the text ``blocking2.0`` with a drop-down box next
   to it. The drop-down box contains four values: an empty space,
   ``?``, ``-``, and ``+``.

#. The developer sets the flag to ``?``.

#. The manager sees the ``blocking2.0``
   flag with a ``?`` value.

#. If the manager thinks the feature should go into the product
   before version 2.0 can be released, he sets the flag to
   ``+``. Otherwise, he sets it to ``-``.

#. Now, every Bugzilla user who looks at the bug knows whether or
   not the bug needs to be fixed before release of version 2.0.

.. _flags-about:

About Flags
===========

.. _flag-values:

Values
------

Flags can have three values:

``?``
    A user is requesting that a status be set. (Think of it as 'A question is being asked'.)

``-``
    The status has been set negatively. (The question has been answered ``no``.)

``+``
    The status has been set positively.
    (The question has been answered ``yes``.)

Actually, there's a fourth value a flag can have --
``unset`` -- which shows up as a blank space. This
just means that nobody has expressed an opinion (or asked
someone else to express an opinion) about this bug or attachment.

.. _flag-askto:

Using flag requests
===================

If a flag has been defined as 'requestable', and a user has enough privileges
to request it (see below), the user can set the flag's status to ``?``.
This status indicates that someone (a.k.a. ``the requester``) is asking
someone else to set the flag to either ``+`` or ``-``.

If a flag has been defined as 'specifically requestable',
a text box will appear next to the flag into which the requester may
enter a Bugzilla username. That named person (a.k.a. ``the requestee``)
will receive an email notifying them of the request, and pointing them
to the bug/attachment in question.

If a flag has *not* been defined as 'specifically requestable',
then no such text-box will appear. A request to set this flag cannot be made of
any specific individual, but must be asked ``to the wind``.
A requester may ``ask the wind`` on any flag simply by leaving the text-box blank.

.. _flag-types:

Two Types of Flags
==================

Flags can go in two places: on an attachment, or on a bug.

.. _flag-type-attachment:

Attachment Flags
----------------

Attachment flags are used to ask a question about a specific
attachment on a bug.

Many Bugzilla installations use this to
request that one developer ``review`` another
developer's code before they check it in. They attach the code to
a bug report, and then set a flag on that attachment called
``review`` to
``review?boss@domain.com``.
boss@domain.com is then notified by email that
he has to check out that attachment and approve it or deny it.

For a Bugzilla user, attachment flags show up in three places:

#. On the list of attachments in the ``Show Bug``
   screen, you can see the current state of any flags that
   have been set to ?, +, or -. You can see who asked about
   the flag (the requester), and who is being asked (the
   requestee).

#. When you ``Edit`` an attachment, you can
   see any settable flag, along with any flags that have
   already been set. This ``Edit Attachment``
   screen is where you set flags to ?, -, +, or unset them.

#. Requests are listed in the ``Request Queue``, which
   is accessible from the ``My Requests`` link (if you are
   logged in) or ``Requests`` link (if you are logged out)
   visible in the footer of all pages.

.. _flag-type-bug:

Bug Flags
---------

Bug flags are used to set a status on the bug itself. You can
see Bug Flags in the ``Show Bug`` and ``Requests``
screens, as described above.

Only users with enough privileges (see below) may set flags on bugs.
This doesn't necessarily include the assignee, reporter, or users with the
``editbugs`` permission.

.. _flags-admin:

Administering Flags
===================

If you have the ``editcomponents`` permission, you can
edit Flag Types from the main administration page. Clicking the
``Flags`` link will bring you to the ``Administer
Flag Types`` page. Here, you can select whether you want
to create (or edit) a Bug flag, or an Attachment flag.

No matter which you choose, the interface is the same, so we'll
just go over it once.

.. _flags-edit:

Editing a Flag
--------------

To edit a flag's properties, just click the flag's name.
That will take you to the same
form as described below (:ref:`flags-create`).

.. _flags-create:

Creating a Flag
---------------

When you click on the ``Create a Flag Type for...``
link, you will be presented with a form. Here is what the fields in
the form mean:

.. _flags-create-field-name:

Name
~~~~

This is the name of the flag. This will be displayed
to Bugzilla users who are looking at or setting the flag.
The name may contain any valid Unicode characters except commas
and spaces.

.. _flags-create-field-description:

Description
~~~~~~~~~~~

The description describes the flag in more detail. It is visible
in a tooltip when hovering over a flag either in the ``Show Bug``
or ``Edit Attachment`` pages. This field can be as
long as you like, and can contain any character you want.

.. _flags-create-field-category:

Category
~~~~~~~~

Default behaviour for a newly-created flag is to appear on
products and all components, which is why ``__Any__:__Any__``
is already entered in the ``Inclusions`` box.
If this is not your desired behaviour, you must either set some
exclusions (for products on which you don't want the flag to appear),
or you must remove ``__Any__:__Any__`` from the Inclusions box
and define products/components specifically for this flag.

To create an Inclusion, select a Product from the top drop-down box.
You may also select a specific component from the bottom drop-down box.
(Setting ``__Any__`` for Product translates to,
``all the products in this Bugzilla``.
Selecting  ``__Any__`` in the Component field means
``all components in the selected product.``)
Selections made, press ``Include``, and your
Product/Component pairing will show up in the ``Inclusions`` box on the right.

To create an Exclusion, the process is the same; select a Product from the
top drop-down box, select a specific component if you want one, and press
``Exclude``. The Product/Component pairing will show up in the
``Exclusions`` box on the right.

This flag *will* and *can* be set for any
products/components that appearing in the ``Inclusions`` box
(or which fall under the appropriate ``__Any__``).
This flag *will not* appear (and therefore cannot be set) on
any products appearing in the ``Exclusions`` box.
*IMPORTANT: Exclusions override inclusions.*

You may select a Product without selecting a specific Component,
but you can't select a Component without a Product, or to select a
Component that does not belong to the named Product. If you do so,
Bugzilla will display an error message, even if all your products
have a component by that name.

*Example:* Let's say you have a product called
``Jet Plane`` that has thousands of components. You want
to be able to ask if a problem should be fixed in the next model of
plane you release. We'll call the flag ``fixInNext``.
But, there's one component in ``Jet Plane,``
called ``Pilot.`` It doesn't make sense to release a
new pilot, so you don't want to have the flag show up in that component.
So, you include ``Jet Plane:__Any__`` and you exclude
``Jet Plane:Pilot``.

.. _flags-create-field-sortkey:

Sort Key
~~~~~~~~

Flags normally show up in alphabetical order. If you want them to
show up in a different order, you can use this key set the order on each flag.
Flags with a lower sort key will appear before flags with a higher
sort key. Flags that have the same sort key will be sorted alphabetically,
but they will still be after flags with a lower sort key, and before flags
with a higher sort key.

*Example:* I have AFlag (Sort Key 100), BFlag (Sort Key 10),
CFlag (Sort Key 10), and DFlag (Sort Key 1). These show up in
the order: DFlag, BFlag, CFlag, AFlag.

.. _flags-create-field-active:

Active
~~~~~~

Sometimes, you might want to keep old flag information in the
Bugzilla database, but stop users from setting any new flags of this type.
To do this, uncheck ``active``. Deactivated
flags will still show up in the UI if they are ?, +, or -, but they
may only be cleared (unset), and cannot be changed to a new value.
Once a deactivated flag is cleared, it will completely disappear from a
bug/attachment, and cannot be set again.

.. _flags-create-field-requestable:

Requestable
~~~~~~~~~~~

New flags are, by default, ``requestable``, meaning that they
offer users the ``?`` option, as well as ``+``
and ``-``.
To remove the ? option, uncheck ``requestable``.

.. _flags-create-field-specific:

Specifically Requestable
~~~~~~~~~~~~~~~~~~~~~~~~

By default this box is checked for new flags, meaning that users may make
flag requests of specific individuals. Unchecking this box will remove the
text box next to a flag; if it is still requestable, then requests may
only be made ``to the wind.`` Removing this after specific
requests have been made will not remove those requests; that data will
stay in the database (though it will no longer appear to the user).

.. _flags-create-field-multiplicable:

Multiplicable
~~~~~~~~~~~~~

Any flag with ``Multiplicable`` set (default for new flags is 'on')
may be set more than once. After being set once, an unset flag
of the same type will appear below it with ``addl.`` (short for
``additional``) before the name. There is no limit to the number of
times a Multiplicable flags may be set on the same bug/attachment.

.. _flags-create-field-cclist:

CC List
~~~~~~~

If you want certain users to be notified every time this flag is
set to ?, -, +, or unset, add them here. This is a comma-separated
list of email addresses that need not be restricted to Bugzilla usernames.

.. _flags-create-grant-group:

Grant Group
~~~~~~~~~~~

When this field is set to some given group, only users in the group
can set the flag to ``+`` and ``-``. This
field does not affect who can request or cancel the flag. For that,
see the ``Request Group`` field below. If this field
is left blank, all users can set or delete this flag. This field is
useful for restricting which users can approve or reject requests.

.. _flags-create-request-group:

Request Group
~~~~~~~~~~~~~

When this field is set to some given group, only users in the group
can request or cancel this flag. Note that this field has no effect
if the ``grant group`` field is empty. You can set the
value of this field to a different group, but both fields have to be
set to a group for this field to have an effect.

.. COMMENT: flags-create

.. _flags-delete:

Deleting a Flag
---------------

When you are at the ``Administer Flag Types`` screen,
you will be presented with a list of Bug flags and a list of Attachment
Flags.

To delete a flag, click on the ``Delete`` link next to
the flag description.

.. warning:: Once you delete a flag, it is *gone* from
   your Bugzilla. All the data for that flag will be deleted.
   Everywhere that flag was set, it will disappear,
   and you cannot get that data back. If you want to keep flag data,
   but don't want anybody to set any new flags or change current flags,
   unset ``active`` in the flag Edit form.

.. COMMENT: flags-admin

.. todo:: We should add a "Uses of Flags" section, here, with examples.

.. COMMENT: flags

