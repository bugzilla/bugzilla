.. _pro-tips:

Pro Tips
########

This section distills some Bugzilla tips and best practices
that have been developed.

Autolinkification
=================

Bugzilla comments are plain text - so typing <U> will
produce less-than, U, greater-than rather than underlined text.
However, Bugzilla will automatically make hyperlinks out of certain
sorts of text in comments. For example, the text
``http://www.bugzilla.org`` will be turned into a link:
`<http://www.bugzilla.org>`_.
Other strings which get linkified in the obvious manner are:

+ bug 12345

+ bugs 123, 456, 789

+ comment 7

+ comments 1, 2, 3, 4

+ bug 23456, comment 53

+ attachment 4321

+ mailto\:george\@example.com

+ george\@example.com

+ ftp\://ftp.mozilla.org

+ Most other sorts of URL

A corollary here is that if you type a bug number in a comment,
you should put the word "bug" before it, so it gets autolinkified
for the convenience of others.

.. _commenting:

Comments
========

If you are changing the fields on a bug, only comment if
either you have something pertinent to say or Bugzilla requires it.
Otherwise, you may spam people unnecessarily with bugmail.
To take an example: a user can set up their account to filter out messages
where someone just adds themselves to the CC field of a bug
(which happens a lot). If you come along, add yourself to the CC field,
and add a comment saying "Adding self to CC", then that person
gets a pointless piece of mail they would otherwise have avoided.

Don't use sigs in comments. Signing your name ("Bill") is acceptable,
if you do it out of habit, but full mail/news-style
four line ASCII art creations are not.

If you feel a bug you filed was incorrectly marked as a
DUPLICATE of another, please question it in your bug, not
the bug it was duped to. Feel free to CC the person who duped it
if they are not already CCed.

.. _markdown:

Markdown
--------

Markdown is a structured plain-text format which lets you write comments that
have more styling than plain text. For example, you may use Markdown for
making a part of your comment look italic or bold in the generated HTML.
Bugzilla supports most of the structures defined by
`standard Markdown <http://daringfireball.net/projects/markdown/basics>`_,
but does **not** support inline images and inline HTML. For a complete
reference on supported Markdown structures, please see the
`syntax help <https://bugzilla.mozilla.org/page.cgi?id=markdown.html>`_ link
next to the Markdown checkbox for new comments.

.. todo:: The above link isn't ideal, but we can't easily link to the user's
          Bugzilla because the docs aren't always on a Bugzilla (e.g.
          when they are on ReadTheDocs). Best solution is to port the
          Markdown guide to ReST.
          Turn this item into a bug after checkin.
          
To use the Markdown feature, make sure that :guilabel:`Enable Markdown
support for comments` is set to :guilabel:`on`
in your :ref:`user-preferences` and that you also check the :guilabel:`Use
Markdown for this comment` option below the comment box when you want to
submit a new comment which uses Markdown.
