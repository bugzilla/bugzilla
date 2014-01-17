

.. _customization:

====================
Customizing Bugzilla
====================

.. _extensions:

Bugzilla Extensions
###################

One of the best ways to customize Bugzilla is by writing a Bugzilla
Extension. Bugzilla Extensions let you modify both the code and
UI of Bugzilla in a way that can be distributed to other Bugzilla
users and ported forward to future versions of Bugzilla with minimal
effort.

See the `Bugzilla Extension
documentation <../html/api/Bugzilla/Extension.html>`_ for information on how to write an Extension.

.. _cust-skins:

Custom Skins
############

Bugzilla allows you to have multiple skins. These are custom CSS and possibly
also custom images for Bugzilla. To create a new custom skin, you have two
choices:

- Make a single CSS file, and put it in the
  :file:`skins/contrib` directory.

- Make a directory that contains all the same CSS file
  names as :file:`skins/standard/`, and put
  your directory in :file:`skins/contrib/`.

After you put the file or the directory there, make sure to run checksetup.pl
so that it can reset the file permissions correctly.

After you have installed the new skin, it will show up as an option in the
user's General Preferences. If you would like to force a particular skin on all
users, just select it in the Default Preferences and then uncheck "Enabled" on
the preference.

.. _cust-templates:

Template Customization
######################

Administrators can configure the look and feel of Bugzilla without
having to edit Perl files or face the nightmare of massive merge
conflicts when they upgrade to a newer version in the future.

Templatization also makes localized versions of Bugzilla possible,
for the first time. It's possible to have Bugzilla's UI language
determined by the user's browser. More information is available in
:ref:`template-http-accept`.

.. _template-directory:

Template Directory Structure
============================

The template directory structure starts with top level directory
named :file:`template`, which contains a directory
for each installed localization. The next level defines the
language used in the templates. Bugzilla comes with English
templates, so the directory name is :file:`en`,
and we will discuss :file:`template/en` throughout
the documentation. Below :file:`template/en` is the
:file:`default` directory, which contains all the
standard templates shipped with Bugzilla.

.. warning:: A directory :file:`data/templates` also exists;
   this is where Template Toolkit puts the compiled versions of
   the templates from either the default or custom directories.
   *Do not* directly edit the files in this
   directory, or all your changes will be lost the next time
   Template Toolkit recompiles the templates.

.. _template-method:

Choosing a Customization Method
===============================

If you want to edit Bugzilla's templates, the first decision
you must make is how you want to go about doing so. There are two
choices, and which you use depends mainly on the scope of your
modifications, and the method you plan to use to upgrade Bugzilla.

The first method of making customizations is to directly edit the
templates found in :file:`template/en/default`.
This is probably the best way to go about it if you are going to
be upgrading Bugzilla through Bzr, because if you then execute
a :command:`bzr update`, any changes you have made will
be merged automagically with the updated versions.

.. note:: If you use this method, and Bzr conflicts occur during an
   update, the conflicted templates (and possibly other parts
   of your installation) will not work until they are resolved.

The second method is to copy the templates to be modified
into a mirrored directory structure under
:file:`template/en/custom`. Templates in this
directory structure automatically override any identically-named
and identically-located templates in the
:file:`default` directory.

.. note:: The :file:`custom` directory does not exist
   at first and must be created if you want to use it.

The second method of customization should be used if you
use the overwriting method of upgrade, because otherwise
your changes will be lost.  This method may also be better if
you are using the Bzr method of upgrading and are going to make major
changes, because it is guaranteed that the contents of this directory
will not be touched during an upgrade, and you can then decide whether
to continue using your own templates, or make the effort to merge your
changes into the new versions by hand.

Using this method, your installation may break if incompatible
changes are made to the template interface.  Such changes should
be documented in the release notes, provided you are using a
stable release of Bugzilla.  If you use using unstable code, you will
need to deal with this one yourself, although if possible the changes
will be mentioned before they occur in the deprecations section of the
previous stable release's release notes.

.. note:: Regardless of which method you choose, it is recommended that
   you run :command:`./checksetup.pl` after
   editing any templates in the :file:`template/en/default`
   directory, and after creating or editing any templates in
   the :file:`custom` directory.

.. warning:: It is *required* that you run :command:`./checksetup.pl` after
   creating a new
   template in the :file:`custom` directory. Failure
   to do so will raise an incomprehensible error message.

.. _template-edit:

How To Edit Templates
=====================

.. note:: If you are making template changes that you intend on submitting back
   for inclusion in standard Bugzilla, you should read the relevant
   sections of the
   `Developers'
   Guide <http://www.bugzilla.org/docs/developer.html>`_.

The syntax of the Template Toolkit language is beyond the scope of
this guide. It's reasonably easy to pick up by looking at the current
templates; or, you can read the manual, available on the
`Template Toolkit home
page <http://www.template-toolkit.org>`_.

One thing you should take particular care about is the need
to properly HTML filter data that has been passed into the template.
This means that if the data can possibly contain special HTML characters
such as <, and the data was not intended to be HTML, they need to be
converted to entity form, i.e. &lt;.  You use the 'html' filter in the
Template Toolkit to do this (or the 'uri' filter to encode special
characters in URLs).  If you forget, you may open up your installation
to cross-site scripting attacks.

Editing templates is a good way of doing a ``poor man's custom
fields``.
For example, if you don't use the Status Whiteboard, but want to have
a free-form text entry box for ``Build Identifier``,
then you can just
edit the templates to change the field labels. It's still be called
status_whiteboard internally, but your users don't need to know that.

.. _template-formats:

Template Formats and Types
==========================

Some CGI's have the ability to use more than one template. For example,
:file:`buglist.cgi` can output itself as RDF, or as two
formats of HTML (complex and simple). The mechanism that provides this
feature is extensible.

Bugzilla can support different types of output, which again can have
multiple formats. In order to request a certain type, you can append
the &ctype=<contenttype> (such as rdf or html) to the
:file:`<cginame>.cgi` URL. If you would like to
retrieve a certain format, you can use the &format=<format>
(such as simple or complex) in the URL.

To see if a CGI supports multiple output formats and types, grep the
CGI for ``get_format``. If it's not present, adding
multiple format/type support isn't too hard - see how it's done in
other CGIs, e.g. config.cgi.

To make a new format template for a CGI which supports this,
open a current template for
that CGI and take note of the INTERFACE comment (if present.) This
comment defines what variables are passed into this template. If
there isn't one, I'm afraid you'll have to read the template and
the code to find out what information you get.

Write your template in whatever markup or text style is appropriate.

You now need to decide what content type you want your template
served as. The content types are defined in the
:file:`Bugzilla/Constants.pm` file in the
:file:`contenttypes`
constant. If your content type is not there, add it. Remember
the three- or four-letter tag assigned to your content type.
This tag will be part of the template filename.

.. note:: After adding or changing a content type, it's suitable to
   edit :file:`Bugzilla/Constants.pm` in order to reflect
   the changes. Also, the file should be kept up to date after an
   upgrade if content types have been customized in the past.

Save the template as :file:`<stubname>-<formatname>.<contenttypetag>.tmpl`.
Try out the template by calling the CGI as
:file:`<cginame>.cgi?format=<formatname>&ctype=<type>` .

.. _template-specific:

Particular Templates
====================

There are a few templates you may be particularly interested in
customizing for your installation.

:command:`index.html.tmpl`:
This is the Bugzilla front page.

:command:`global/header.html.tmpl`:
This defines the header that goes on all Bugzilla pages.
The header includes the banner, which is what appears to users
and is probably what you want to edit instead.  However the
header also includes the HTML HEAD section, so you could for
example add a stylesheet or META tag by editing the header.

:command:`global/banner.html.tmpl`:
This contains the ``banner``, the part of the header
that appears
at the top of all Bugzilla pages.  The default banner is reasonably
barren, so you'll probably want to customize this to give your
installation a distinctive look and feel.  It is recommended you
preserve the Bugzilla version number in some form so the version
you are running can be determined, and users know what docs to read.

:command:`global/footer.html.tmpl`:
This defines the footer that goes on all Bugzilla pages.  Editing
this is another way to quickly get a distinctive look and feel for
your Bugzilla installation.

:command:`global/variables.none.tmpl`:
This defines a list of terms that may be changed in order to
``brand`` the Bugzilla instance In this way, terms
like ``bugs`` can be replaced with ``issues``
across the whole Bugzilla installation. The name
``Bugzilla`` and other words can be customized as well.

:command:`list/table.html.tmpl`:
This template controls the appearance of the bug lists created
by Bugzilla. Editing this template allows per-column control of
the width and title of a column, the maximum display length of
each entry, and the wrap behaviour of long entries.
For long bug lists, Bugzilla inserts a 'break' every 100 bugs by
default; this behaviour is also controlled by this template, and
that value can be modified here.

:command:`bug/create/user-message.html.tmpl`:
This is a message that appears near the top of the bug reporting page.
By modifying this, you can tell your users how they should report
bugs.

:command:`bug/process/midair.html.tmpl`:
This is the page used if two people submit simultaneous changes to the
same bug.  The second person to submit their changes will get this page
to tell them what the first person did, and ask if they wish to
overwrite those changes or go back and revisit the bug.  The default
title and header on this page read "Mid-air collision detected!"  If
you work in the aviation industry, or other environment where this
might be found offensive (yes, we have true stories of this happening)
you'll want to change this to something more appropriate for your
environment.

:command:`bug/create/create.html.tmpl` and
:command:`bug/create/comment.txt.tmpl`:
You may not wish to go to the effort of creating custom fields in
Bugzilla, yet you want to make sure that each bug report contains
a number of pieces of important information for which there is not
a special field. The bug entry system has been designed in an
extensible fashion to enable you to add arbitrary HTML widgets,
such as drop-down lists or textboxes, to the bug entry page
and have their values appear formatted in the initial comment.
A hidden field that indicates the format should be added inside
the form in order to make the template functional. Its value should
be the suffix of the template filename. For example, if the file
is called :file:`create-cust.html.tmpl`, then

::

    <input type="hidden" name="format" value="cust">

should be used inside the form.

An example of this is the mozilla.org
`guided
bug submission form <|landfillbase|enter_bug.cgi?product=WorldControl;format=guided>`_. The code for this comes with the Bugzilla
distribution as an example for you to copy. It can be found in the
files
:file:`create-guided.html.tmpl` and
:file:`comment-guided.html.tmpl`.

So to use this feature, create a custom template for
:file:`enter_bug.cgi`. The default template, on which you
could base it, is
:file:`custom/bug/create/create.html.tmpl`.
Call it :file:`create-<formatname>.html.tmpl`, and
in it, add widgets for each piece of information you'd like
collected - such as a build number, or set of steps to reproduce.

Then, create a template like
:file:`custom/bug/create/comment.txt.tmpl`, and call it
:file:`comment-<formatname>.txt.tmpl`. This
template should reference the form fields you have created using
the syntax :file:`[% form.<fieldname> %]`. When a
bug report is
submitted, the initial comment attached to the bug report will be
formatted according to the layout of this template.

For example, if your custom enter_bug template had a field

::

    <input type="text" name="buildid" size="30">

and then your comment.txt.tmpl had

::

    BuildID: \[% form.buildid %]

then something like

::

    BuildID: 20020303

would appear in the initial comment.

.. _template-http-accept:

Configuring Bugzilla to Detect the User's Language
==================================================

Bugzilla honours the user's Accept: HTTP header. You can install
templates in other languages, and Bugzilla will pick the most appropriate
according to a priority order defined by you. Many
language templates can be obtained from `<http://www.bugzilla.org/download.html#localizations>`_. Instructions
for submitting new languages are also available from that location.

.. _cust-change-permissions:

Customizing Who Can Change What
###############################

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

.. _integration:

Integrating Bugzilla with Third-Party Tools
###########################################

Many utilities and applications can integrate with Bugzilla,
either on the client- or server-side. None of them are maintained
by the Bugzilla community, nor are they tested during our
QA tests, so use them at your own risk. They are listed at
`<https://wiki.mozilla.org/Bugzilla:Addons>`_.


