.. _templates:

Templates
#########

Administrators can configure the look and feel of Bugzilla without
having to edit Perl files or face the nightmare of massive merge
conflicts when they upgrade to a newer version in the future.

It's possible to have Bugzilla's UI language
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
   the templates. *Do not* directly edit the files in this
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
This is probably the best way for minor changes, because when you upgrade
Bugzilla, either the source code management system or the :file:`patch` tool
will merge your changes into the new version for you.

On the downside, if the merge fails then Bugzilla will not work properly until
you have fixed the problem and re-integrated your code.

The second method is to copy the templates to be modified
into a mirrored directory structure under
:file:`template/en/custom`. Templates in this
directory structure automatically override any identically-named
and identically-located templates in the
:file:`default` directory.

The :file:`custom` directory does not exist at first and must be created if
you want to use it.

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
XXX Need to describe the use of this file

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
bug submission form <http://landfill.bugzilla.org/bugzilla-tip/enter_bug.cgi?product=WorldControl;format=guided>`_. The code for this comes with the Bugzilla
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
