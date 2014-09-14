.. _categorization:

==============================================================
Classifications, Products, Components, Versions and Milestones
==============================================================

Classifications
###############

Classifications tend to be used in order to group several related
products into one distinct entity.

The classifications layer is disabled by default; it can be turned
on or off using the useclassification parameter,
in the *Bug Fields* section of the edit parameters screen.

Access to the administration of classifications is controlled using
the *editclassifications* system group, which defines
a privilege for creating, destroying, and editing classifications.

When activated, classifications will introduce an additional
step when filling bugs (dedicated to classification selection), and they
will also appear in the advanced search form.

.. _products:

Products
########

Products typically represent real-world
shipping products. Products can be given
:ref:`classifications`.
For example, if a company makes computer games,
they could have a classification of "Games", and a separate
product for each game. This company might also have a
``Common`` product for units of technology used
in multiple games, and perhaps a few special products that
represent items that are not actually shipping products
(for example, "Website", or "Administration").

Many of Bugzilla's settings are configurable on a per-product
basis. The number of ``votes`` available to
users is set per-product, as is the number of votes
required to move a bug automatically from the UNCONFIRMED
status to the CONFIRMED status.

When creating or editing products the following options are
available:

Product
    The name of the product

Description
    A brief description of the product

Default milestone
    Select the default milestone for this product.

Closed for bug entry
    Select this box to prevent new bugs from being
    entered against this product.

Maximum votes per person
    Maximum votes a user is allowed to give for this
    product

Maximum votes a person can put on a single bug
    Maximum votes a user is allowed to give for this
    product in a single bug

Confirmation threshold
    Number of votes needed to automatically remove any
    bug against this product from the UNCONFIRMED state

Version
    Specify which version of the product bugs will be
    entered against.

Create chart datasets for this product
    Select to make chart datasets available for this product.

When editing a product there is also a link to edit Group Access Controls,
see :ref:`product-group-controls`.

.. _create-product:

Creating New Products
=====================

To create a new product:

#. Select ``Administration`` from the footer and then
   choose ``Products`` from the main administration page.

#. Select the ``Add`` link in the bottom right.

#. Enter the name of the product and a description. The
   Description field may contain HTML.

#. When the product is created, Bugzilla will give a message
   stating that a component must be created before any bugs can
   be entered against the new product. Follow the link to create
   a new component. See :ref:`components` for more
   information.

.. _edit-products:

Editing Products
================

To edit an existing product, click the "Products" link from the
"Administration" page. If the 'useclassification' parameter is
turned on, a table of existing classifications is displayed,
including an "Unclassified" category. The table indicates how many products
are in each classification. Click on the classification name to see its
products. If the 'useclassification' parameter is not in use, the table
lists all products directly. The product table summarizes the information
about the product defined
when the product was created. Click on the product name to edit these
properties, and to access links to other product attributes such as the
product's components, versions, milestones, and group access controls.

.. _comps-vers-miles-products:

Adding or Editing Components, Versions and Target Milestones
============================================================

To edit existing, or add new, Components, Versions or Target Milestones
to a Product, select the "Edit Components", "Edit Versions" or "Edit
Milestones" links from the "Edit Product" page. A table of existing
Components, Versions or Milestones is displayed. Click on a item name
to edit the properties of that item. Below the table is a link to add
a new Component, Version or Milestone.

For more information on components, see :ref:`components`.

For more information on versions, see :ref:`versions`.

For more information on milestones, see :ref:`milestones`.

.. _product-group-controls:

Assigning Group Controls to Products
====================================

On the ``Edit Product`` page, there is a link called
``Edit Group Access Controls``. The settings on this page
control the relationship of the groups to the product being edited.

Group Access Controls are an important aspect of using groups for
isolating products and restricting access to bugs filed against those
products. For more information on groups, including how to create, edit
add users to, and alter permission of, see :ref:`groups`.

After selecting the "Edit Group Access Controls" link from the "Edit
Product" page, a table containing all user-defined groups for this
Bugzilla installation is displayed. The system groups that are created
when Bugzilla is installed are not applicable to Group Access Controls.
Below is description of what each of these fields means.

Groups may be applicable (e.g bugs in this product can be associated
with this group) , default (e.g. bugs in this product are in this group
by default), and mandatory (e.g. bugs in this product must be associated
with this group) for each product. Groups can also control access
to bugs for a given product, or be used to make bugs for a product
totally read-only unless the group restrictions are met. The best way to
understand these relationships is by example. See
:ref:`group-control-examples` for examples of
product and group relationships.

.. note:: Products and Groups are not limited to a one-to-one relationship.
   Multiple groups can be associated with the same product, and groups
   can be associated with more than one product.

If any group has *Entry* selected, then the
product will restrict bug entry to only those users
who are members of *all* the groups with
*Entry* selected.

If any group has *Canedit* selected,
then the product will be read-only for any users
who are not members of *all* of the groups with
*Canedit* selected. *Only* users who
are members of all the *Canedit* groups
will be able to edit bugs for this product. This is an additional
restriction that enables finer-grained control over products rather
than just all-or-nothing access levels.

The following settings let you
choose privileges on a *per-product basis*.
This is a convenient way to give privileges to
some users for some products only, without having
to give them global privileges which would affect
all products.

Any group having *editcomponents*
selected  allows users who are in this group to edit all
aspects of this product, including components, milestones
and versions.

Any group having *canconfirm* selected
allows users who are in this group to confirm bugs
in this product.

Any group having *editbugs* selected allows
users who are in this group to edit all fields of
bugs in this product.

The *MemberControl* and
*OtherControl* are used in tandem to determine which
bugs will be placed in this group. The only allowable combinations of
these two parameters are listed in a table on the "Edit Group Access Controls"
page. Consult this table for details on how these fields can be used.
Examples of different uses are described below.

.. _group-control-examples:

Common Applications of Group Controls
=====================================

The use of groups is best explained by providing examples that illustrate
configurations for common use cases. The examples follow a common syntax:
*Group: Entry, MemberControl, OtherControl, CanEdit,
EditComponents, CanConfirm, EditBugs*. Where "Group" is the name
of the group being edited for this product. The other fields all
correspond to the table on the "Edit Group Access Controls" page. If any
of these options are not listed, it means they are not checked.

Basic Product/Group Restriction
-------------------------------

Suppose there is a product called "Bar". The
"Bar" product can only have bugs entered against it by users in the
group "Foo". Additionally, bugs filed against product "Bar" must stay
restricted to users to "Foo" at all times. Furthermore, only members
of group "Foo" can edit bugs filed against product "Bar", even if other
users could see the bug. This arrangement would achieved by the
following:

::

    Product Bar:
    foo: ENTRY, MANDATORY/MANDATORY, CANEDIT

Perhaps such strict restrictions are not needed for product "Bar". A
more lenient way to configure product "Bar" and group "Foo" would be:

::

    Product Bar:
    foo: ENTRY, SHOWN/SHOWN, EDITCOMPONENTS, CANCONFIRM, EDITBUGS

The above indicates that for product "Bar", members of group "Foo" can
enter bugs. Any one with permission to edit a bug against product "Bar"
can put the bug
in group "Foo", even if they themselves are not in "Foo". Anyone in group
"Foo" can edit all aspects of the components of product "Bar", can confirm
bugs against product "Bar", and can edit all fields of any bug against
product "Bar".

General User Access With Security Group
---------------------------------------

To permit any user to file bugs against "Product A",
and to permit any user to submit those bugs into a
group called "Security":

::

    Product A:
    security: SHOWN/SHOWN

General User Access With A Security Product
-------------------------------------------

To permit any user to file bugs against product called "Security"
while keeping those bugs from becoming visible to anyone
outside the group "SecurityWorkers" (unless a member of the
"SecurityWorkers" group removes that restriction):

::

    Product Security:
    securityworkers: DEFAULT/MANDATORY

Product Isolation With a Common Group
-------------------------------------

To permit users of "Product A" to access the bugs for
"Product A", users of "Product B" to access the bugs for
"Product B", and support staff, who are members of the "Support
Group" to access both, three groups are needed:

#. Support Group: Contains members of the support staff.

#. AccessA Group: Contains users of product A and the Support group.

#. AccessB Group: Contains users of product B and the Support group.

Once these three groups are defined, the product group controls
can be set to:

::

    Product A:
    AccessA: ENTRY, MANDATORY/MANDATORY
    Product B:
    AccessB: ENTRY, MANDATORY/MANDATORY

Perhaps the "Support Group" wants more control. For example,
the "Support Group"  could be permitted to make bugs inaccessible to
users of both groups "AccessA" and "AccessB".
Then, the "Support Group" could be permitted to publish
bugs relevant to all users in a third product (let's call it
"Product Common") that is read-only
to anyone outside the "Support Group". In this way the "Support Group"
could control bugs that should be seen by both groups.
That configuration would be:

::

    Product A:
    AccessA: ENTRY, MANDATORY/MANDATORY
    Support: SHOWN/NA
    Product B:
    AccessB: ENTRY, MANDATORY/MANDATORY
    Support: SHOWN/NA
    Product Common:
    Support: ENTRY, DEFAULT/MANDATORY, CANEDIT

Make a Product Read Only
------------------------

Sometimes a product is retired and should no longer have
new bugs filed against it (for example, an older version of a software
product that is no longer supported). A product can be made read-only
by creating a group called "readonly" and adding products to the
group as needed:

::

    Product A:
    ReadOnly: ENTRY, NA/NA, CANEDIT

.. note:: For more information on Groups outside of how they relate to products
   see :ref:`groups`.

.. _components:

Components
##########

Components are subsections of a Product. E.g. the computer game
you are designing may have a "UI"
component, an "API" component, a "Sound System" component, and a
"Plugins" component, each overseen by a different programmer. It
often makes sense to divide Components in Bugzilla according to the
natural divisions of responsibility within your Product or
company.

Each component has a default assignee and (if you turned it on in the parameters),
a QA Contact. The default assignee should be the primary person who fixes bugs in
that component. The QA Contact should be the person who will ensure
these bugs are completely fixed. The Assignee, QA Contact, and Reporter
will get email when new bugs are created in this Component and when
these bugs change. Default Assignee and Default QA Contact fields only
dictate the
*default assignments*;
these can be changed on bug submission, or at any later point in
a bug's life.

To create a new Component:

#. Select the ``Edit components`` link
   from the ``Edit product`` page

#. Select the ``Add`` link in the bottom right.

#. Fill out the ``Component`` field, a
   short ``Description``, the
   ``Default Assignee``, ``Default CC List``
   and ``Default QA Contact`` (if enabled).
   The ``Component Description`` field may contain a
   limited subset of HTML tags. The ``Default Assignee``
   field must be a login name already existing in the Bugzilla database.

.. _versions:

Versions
########

Versions are the revisions of the product, such as "Flinders
3.1", "Flinders 95", and "Flinders 2000". Version is not a multi-select
field; the usual practice is to select the earliest version known to have
the bug.

To create and edit Versions:

#. From the "Edit product" screen, select "Edit Versions"

#. You will notice that the product already has the default
   version "undefined". Click the "Add" link in the bottom right.

#. Enter the name of the Version. This field takes text only.
   Then click the "Add" button.

.. _milestones:

Milestones
##########

Milestones are "targets" that you plan to get a bug fixed by. For
example, you have a bug that you plan to fix for your 3.0 release, it
would be assigned the milestone of 3.0.

.. note:: Milestone options will only appear for a Product if you turned
   on the "usetargetmilestone" parameter in the "Bug Fields" tab of the
   "Parameters" page.

To create new Milestones, and set Default Milestones:

#. Select "Edit milestones" from the "Edit product" page.

#. Select "Add" in the bottom right corner.

#. Enter the name of the Milestone in the "Milestone" field. You
   can optionally set the "sortkey", which is a positive or negative
   number (-32768 to 32767) that defines where in the list this particular
   milestone appears. This is because milestones often do not
   occur in alphanumeric order For example, "Future" might be
   after "Release 1.2". Select "Add".
