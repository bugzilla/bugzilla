.. _localizing-templates:

Localizing The Templates
########################

.. note:: Use an UTF-8-compliant editor, like Gedit, Kate or Emacs under
          GNU/Linux systems or Notepad++ under Windows systems, and make sure
          you save the templates using the UTF-8 encoding.

Templates contain both code and localizable strings mixed together. So the
question arises: what is to be localized and what is not? Here are some
examples to help you localize the correct parts of each file.

You can see at the top of each template file lines like these:

.. code-block:: text

  [%# This Source Code Form is subject to the terms of the Mozilla Public
    # License, v. 2.0. If a copy of the MPL was not distributed with this
    # file, You can obtain one at http://mozilla.org/MPL/2.0/.
    #
    # This Source Code Form is "Incompatible With Secondary Licenses", as
    # defined by the Mozilla Public License, v. 2.0.
    #%]

DO NOT translate any text located between ``[%#`` and ``#%]``. Such text is a
comment.

Here are some examples of what does need to be translated:

.. raw:: html

  <pre>
  [% title = BLOCK %]<mark>Delete Component '</mark>[% comp.name FILTER html %]<mark>'
  of Product '</mark>[% product.name FILTER html %]<mark>'</mark>
    [% END %]

  [% PROCESS global/header.html.tmpl
    title = title
  %]
  
  &lt;table border="1" cellpadding="4" cellspacing="0"&gt;
  &lt;tr bgcolor="#6666FF"&gt;
    &lt;th valign="top" align="left"&gt;<mark>Field</mark>&lt;/th&gt;
    &lt;th valign="top" align="left"&gt;<mark>Value</mark>&lt;/th&gt;
  &lt;/tr&gt;
  </pre>

As a general rule, never
translate capitalized words enclosed between ``[%`` and ``%]`` - these are
Template Toolkit directives. Here is the localized version of the above:

.. raw:: html

  <pre>
  [% title = BLOCK %]<mark>Supprimer le composant « </mark>[% comp.name FILTER html %]<mark> »
  du produit « </mark>[% product.name FILTER html %]<mark> »</mark>
    [% END %]
  
  [% PROCESS global/header.html.tmpl
    title = title
  %]
  
  &lt;table border="1" cellpadding="4" cellspacing="0"&gt;
  &lt;tr bgcolor="#6666FF"&gt;
    &lt;th valign="top" align="left"&gt;<mark>Champ</mark>&lt;/th&gt;
    &lt;th valign="top" align="left"&gt;<mark>Valeur</mark>&lt;/th&gt;
  &lt;/tr&gt;
  </pre>

Another common occurrence in the templates is text enclosed between an opening
and a closing tag, or in an HTML attribute value:

.. raw:: html

  <pre>
  &lt;td valign="top"&gt;<mark>Description du produit :</mark>&lt;/td&gt;
  
  &lt;td valign="top"&gt;[% IF product.disallow_new %]<mark>Oui</mark>[% ELSE %]<mark>Non</mark>[% END %]&lt;/td&gt;
  
    &lt;a title="<mark>Liste des</mark> [% terms.bugs %] <mark>pour le composant « </mark>[% comp.name FILTER html %]<mark> »</mark>"
       href="buglist.cgi?component=[% comp.name FILTER url_quote %]&amp;product=
            [%- product.name FILTER url_quote %]"&gt;[% comp.bug_count %]&lt;/a&gt;
  </pre>

You will encounter many buttons you will want to localize. These look like this:

.. raw:: html

  <pre>
    &lt;input type="submit" id="create" value="<mark>Add</mark>"&gt;
    &lt;input type="hidden" name="action" value="new"&gt;
    &lt;input type="hidden" name='product' value="[% product.name FILTER html %]"&gt;
    &lt;input type="hidden" name="token" value="[% token FILTER html %]"&gt;
  </pre>

Whenever you see this, the only line that needs to be localized is the one
with ``type="submit"``. DO NOT translate lines with ``type="hidden"``:

.. raw:: html

  <pre>
    &lt;input type="submit" id="create" value="<mark>Ajouter</mark>"&gt;
    &lt;input type="hidden" name="action" value="new"&gt;
    &lt;input type="hidden" name='product' value="[% product.name FILTER html %]"&gt;
    &lt;input type="hidden" name="token" value="[% token FILTER html %]"&gt;
  </pre>


Some of the templates are a bit special. One such is
:file:`/template/en/default/global/variables.none.tmpl`.
This file contains several terms that are be substituted all around the
template files. In particular, it contains code so the administrator can easily and
consistently use whatever alternative term their organization uses for "bug"
and also for "Bugzilla" (i.e. the name of the system). Whenever you see expressions like
``&terms.ABug`` or ``&terms.bugs`` in templates, they will be replaced in the
user interface with the corresponding value from this file.

As these are commonly-requested changes, you probably want to retain this
flexibility in your localization, although you may have to alter exactly how
it works if your language does not have exact equivalents for "a" and "the".

.. raw:: html
 
  <pre>
  [% terms = {
    "bug" => "<mark>bug</mark>",
    "Bug" => "<mark>Bug</mark>",
    "abug" => "<mark>a bug</mark>",
    "Abug" => "<mark>A bug</mark>",
    "ABug" => "<mark>A Bug</mark>",
    "bugs" => "<mark>bugs</mark>",
    "Bugs" => "<mark>Bugs</mark>",
    "zeroSearchResults" => "<mark>Zarro Boogs found</mark>",
    "bit" => "<mark>bit</mark>",
    "bits" => "<mark>bits</mark>",
    "Bugzilla" => "<mark>Bugzilla</mark>"
    }
  %]
  </pre>

You need to come up with an equivalent set of mappings for your language, and
then whenever you are talking about bugs in the user interface, use your
equivalent of ``&terms.ABug`` or ``&terms.bugs`` and friends instead.
