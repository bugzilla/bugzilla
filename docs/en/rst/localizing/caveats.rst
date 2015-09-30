.. _caveats:

Template Caveats
################

================
[% %] and [%+ %]
================

``[% %]`` is used by Template Toolkit to enclose some TT code, which will be
often be replaced by a variable or something else when the template is
rendered.

Generally, you should follow the exact text layout of the English version, but
if you need to change the position of a ``[% %]`` block in a line, you should
be aware of this rule: when two ``[% %]`` blocks are following each other,
the second member will not be separated with a space from the first one, even
if you separate them with a space. For instance, these lines of template code:

.. raw:: html

  <pre>
    [% ELSIF message_tag == "bug_duplicate_of" %]
      This [% terms.bug %] has been marked as a duplicate of <mark>[% terms.bug %] [% dupe_of FILTER html %]</mark>
  </pre>

will display in the browser as:

.. code-block:: text

  This bug has been marked as duplicate of bug12345

To preserve whitespace, you should add a "+" sign inside the second member:

.. raw:: html

  <pre>
    [% ELSIF message_tag == "bug_duplicate_of" %]
       This [% terms.bug %] has been marked as a duplicate of [% terms.bug %] [%<mark>+</mark> dupe_of FILTER html %]
  </pre>

Will then be displayed as:

.. code-block:: text

  This bug has been marked as duplicate of bug 12345

This is the same when a [% %] member is at the beginning of a new line. These
lines of template code:

.. code-block:: text

          [% IF groups_added_to.size %]
            <li>
              The account has been added to the
              [% groups_added_to.join(', ') FILTER html %]
              group[% 's' IF groups_added_to.size &gt; 1 %].
            </li>
          [% END %]

will be shown as:

.. code-block:: text

  The account has been added to thebz_sudo_protect group.

Again, insert a "+" sign:

.. raw:: html

  <pre>
          [% IF groups_added_to.size %]
            &lt;li&gt;
              The account has been added to the
              [%<mark>+</mark> groups_added_to.join(', ') FILTER html %]
              group[% 's' IF groups_added_to.size &gt; 1 %].
            &lt;/li&gt;
          [% END %]
  </pre>

So that the sentence is displayed as:

.. code-block:: text

  The account has been added to the bz_sudo_protect group.

Sometimes, pluralization is dealt with using explicit Template Toolkit code,
which needs to be altered for your language.

For example, if one wanted to localize the previous example into French,
the words order would not be not correct and the markup has to be rearranged.
The member ``[% groups_added_to.join(', ') FILTER html %]`` will actually display
the name of one group or several group names separated with a comma and a space (', ').
The member ``[% 's' IF groups_added_to.size > 1 %]`` will add an "s"
to the word "group" if there is more than one. In French, the group name should be put
after the term "group" and words need to be declensed when plural is used. That
would give for instance the following:

.. code-block:: text

          [% IF groups_added_to.size %]
            <li>
              Le compte a été ajouté
              [% IF groups_added_to.size &gt; 1 %]
              aux groupes[% ELSE %]au groupe[% END %][%+ groups_added_to.join(', ') FILTER html %].
            </li>
          [% END %]

The browser would then display for one group:

.. raw:: html

  Le compte a été ajouté <mark>au groupe</mark> bz_sudo_protect

And for several groups:

.. raw:: html

  Le compte a été ajouté <mark>aux groupes</mark> bz_sudo_protect, canconfirm, editbugs

===============================
Double quotes and single quotes
===============================

Template Toolkit strings in directives are quote-delimited, and can use either
single or double quotes. But, obviously, you can't put double quotes inside
a double-quoted string. The following example will break the user interface:

.. code-block:: text

    [% ELSIF message_tag == "buglist_adding_field" %]
      [% title = "Adding field to search page..." %]
      [% link  = "Click here if the page "does not" redisplay automatically." %]


Instead, you can escape them with a backslash ("\"):

.. code-block:: text

    [% ELSIF message_tag == "buglist_adding_field" %]
      [% title = "Adding field to search page..." %]
      [% link  = "Click here if the page \"does not\" redisplay automatically." %]


Or you can substitute the surrounding double quotes with single quotes:

.. code-block:: text

    [% ELSIF message_tag == "buglist_adding_field" %]
      [% title = "Adding field to search page..." %]
      [% link  = 'Click here if the page "does not" redisplay automatically.' %]

===========
Declensions
===========

English only deals with one plural form and has no declension. Your locale
might need to implement declensions, and reorder words inside a sentence.

Let's say we have the following:

.. code-block:: text

    [% IF !Param("allowbugdeletion") %]
    <p>
      Sorry, there
  
      [% IF comp.bug_count &gt; 1 %] 
        are [% comp.bug_count %] [%+ terms.bugs %] 
      [% ELSE %]
         is [% comp.bug_count %] [%+ terms.bug %] 
      [% END %]
  
      pending for this component. You should reassign
  
      [% IF comp.bug_count &gt; 1 %]
         these [% terms.bugs %]
      [% ELSE %]
         this [% terms.bug %]
      [% END %]
  
      to another component before deleting this component.
    </p>
    [% ELSE %]

Here, the following expression comp.bug_count obviously gives the count number of bugs
for a component. ``IF comp.bug_count > 1`` means "if there are more than one bug".

Let's say your language has to deal with three plural forms and that the terms "bug" and
"pending" should be declensed as well.

First, you'll have to populate the :file:`/template/en/default/global/variables.none.tmp`
file with the declensions for "bug", which would give something like:

.. code-block:: text

  [% terms = {
    "bug0" => "declension for zero bug",
    "bug" => "declension for one bug",
    "bug2" => "declension for two bugs",
    "bug3" => "declension for three bugs",
    "bugs" => "declension for more than three bugs",
  

Then, the previous code should look like:

.. code-block:: text

    [% IF !Param("allowbugdeletion") %]
    <p>
      Sorry, there
  
      [% IF comp.bug_count > 3 %] 
        are [% comp.bug_count %] pending [% terms.bugs %] 
      [% ELSE %]
        [% IF comp.bug_count == 0 %] 
         is [% comp.bug_count %] pending [% terms.bug0 %] 
      [% ELSE %]
        [% IF comp.bug_count == 1 %] 
         is [% comp.bug_count %] pending [% terms.bug %]
      [% ELSE %]
        [% IF comp.bug_count == 2 %] 
         are [% comp.bug_count %] pending [% terms.bug2 %]
      [% ELSE %]
        [% IF comp.bug_count == 3 %] 
         are [% comp.bug_count %] pending [% terms.bug3 %] 
      [% END %]
  
      for this component. You should reassign
  
      [% IF comp.bug_count &gt; 1 %]
         these [% terms.bugs %]
      [% ELSE %]
         this [% terms.bug %]
      [% END %]
  
      to another component before deleting this component.
    </p>
    [% ELSE %]

==========
$terms.foo
==========

As seen previously, term substitutions can be made across all template files.
Such substitutions are defined in ``*.none.tmpl`` files, which are:

* template/en/default/global/field-descs.none.tmpl
* template/en/default/global/variables.none.tmpl
* template/en/default/global/value-descs.none.tmpl
* template/en/default/global/reason-descs.none.tmpl
* template/en/default/global/setting-descs.none.tmpl
* template/en/default/bug/field-help.none.tmpl

These variables appear in the template files under three different forms.
``[% terms.foo %]`` is the standard, simple substitution of a term into a run
of text. ``$terms.foo`` is used when substituting into a Template Toolkit
string, and ``${terms.foo}`` is used when you need to separate the variable
name from the surrounding content to resolve ambiguity.

To illustrate this last point: during your localizing contribution, you may
have to reorganize sentences, and sometimes a variable of the form
``$terms.foo`` will come at the end of a sentence which ends with a full stop,
like this:

.. raw:: html

  <pre>
    defaultplatform => "Plateforme qui est pré-sélectionnée dans le formulaire de soumission " _
                       "de <mark>$terms.bug.</mark>&lt;br&gt; " _
                       "Vous pouvez laisser ce champ vide : " _
                       "Bugzilla utilisera alors la plateforme indiquée par le navigateur.",
  </pre>

If you leave it like that, the substitution would not take place and the
result in the user interface would be wrong. Instead, change the form
``$terms.foo`` into the form ``${terms.foo}``, like this:

.. raw:: html

  <pre>
    defaultplatform => "Plateforme qui est pré-sélectionnée dans le formulaire de soumission " _
                       "de <mark>${terms.bug}.</mark>&lt;br&gt; " _
                       "Vous pouvez laisser ce champ vide : " _
                       "Bugzilla utilisera alors la plateforme indiquée par le navigateur.",
  </pre>

========
b[% %]ug
========

Once and a while you would find something like:

.. code-block:: text

  A b[% %]ug on b[% %]ugs.debian.org.

You remember that the file :file:`variables.none.tmpl` holds the substitutions
for different terms. The release process of Bugzilla has a script that
parses all the templates to check if you wrote the bare word "bug" instead of
"$terms.bug" or similar, to make sure that this feature keeps working.

In the example above, we really want to write the term "bug" and we neither
want it to be substituted afterwards nor be warned by the test script.

This check only looks at the English terms bug, bugs, and Bugzilla, so you can
safely ignore the ``[% %]`` and localize ``b[% %]ug``, but you would keep
``b[% %]ugs.debian.org`` unchanged as it's a URL.
