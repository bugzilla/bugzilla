Comments
========

.. _rest_comments:

Get Comments
------------

This allows you to get data about comments, given a bug ID or comment ID.

**Request**

To get all comments for a particular bug using the bug ID or alias:

.. code-block:: text

   GET /rest/bug/(id_or_alias)/comment

To get a specific comment based on the comment ID:

.. code-block:: text

   GET /rest/bug/comment/(comment_id)

===============  ========  ======================================================
name             type      description
===============  ========  ======================================================
**id_or_alias**  mixed     A single integer bug ID or alias.
**comment_id**   int       A single integer comment ID.
new_since        datetime  If specified, the method will only return comments
                           *newer* than this time. This only affects comments
                           returned from the ``ids`` argument. You will always be
                           returned all comments you request in the
                           ``comment_ids`` argument, even if they are older than
                           this date.
===============  ========  ======================================================

**Response**

.. code-block:: js

   {
     "bugs": {
       "35": {
         "comments": [
           {
             "time": "2000-07-25T13:50:04Z",
             "text": "test bug to fix problem in removing from cc list.",
             "bug_id": 35,
             "count": 0,
             "attachment_id": null,
             "is_private": false,
             "tags": [],
             "creator": "user@bugzilla.org",
             "creation_time": "2000-07-25T13:50:04Z",
             "id": 75
           }
         ]
       }
     },
     "comments": {}
   }

Two items are returned:

``bugs`` This is used for bugs specified in ``ids``. This is an object,
where the keys are the numeric IDs of the bugs, and the value is
a object with a single key, ``comments``, which is an array of comments.
(The format of comments is described below.)

Any individual bug will only be returned once, so if you specify an ID
multiple times in ``ids``, it will still only be returned once.

``comments`` Each individual comment requested in ``comment_ids`` is
returned here, in a object where the numeric comment ID is the key,
and the value is the comment. (The format of comments is described below.)

A "comment" as described above is a object that contains the following items:

=============  ========  ========================================================
name           type      description
=============  ========  ========================================================
id             int       The globally unique ID for the comment.
bug_id         int       The ID of the bug that this comment is on.
attachment_id  int       If the comment was made on an attachment, this will be
                         the ID of that attachment. Otherwise it will be null.
count          int       The number of the comment local to the bug. The
                         Description is 0, comments start with 1.
text           string    The actual text of the comment.
creator        string    The login name of the comment's author.
time           datetime  The time (in Bugzilla's timezone) that the comment was
                         added.
creation_time  datetime  This is exactly same as the ``time`` key. Use this
                         field instead of ``time`` for consistency with other
                         methods including :ref:`rest_single_bug` and
                         :ref:`rest_attachments`.

                         For compatibility, ``time`` is still usable. However,
                         please note that ``time`` may be deprecated and removed
                         in a future release.

is_private     boolean   ``true`` if this comment is private (only visible to a
                         certain group called the "insidergroup"), ``false``
                         otherwise.
=============  ========  ========================================================

**Errors**

This method can throw all the same errors as :ref:`rest_single_bug`. In addition,
it can also throw the following errors:

* 110 (Comment Is Private)
  You specified the id of a private comment in the "comment_ids"
  argument, and you are not in the "insider group" that can see
  private comments.
* 111 (Invalid Comment ID)
  You specified an id in the "comment_ids" argument that is invalid--either
  you specified something that wasn't a number, or there is no comment with
  that id.

.. _rest_add_comment:

Create Comments
---------------

This allows you to add a comment to a bug in Bugzilla.

**Request**

To create a comment on a current bug.

.. code-block:: text

   POST /rest/bug/(id)/comment

.. code-block:: js

   {
     "ids" : [123,..],
     "comment" : "This is an additional comment",
     "is_private" : false
   }

``ids`` is optional in the data example above and can be used to specify adding
a comment to more than one bug at the same time.

===========  =======  ===========================================================
name         type     description
===========  =======  ===========================================================
**id**       int      The ID or alias of the bug to append a comment to.
ids          array    List of integer bug IDs to add the comment to.
**comment**  string   The comment to append to the bug. If this is empty
                      or all whitespace, an error will be thrown saying that you
                      did not set the ``comment`` parameter.
is_private   boolean  If set to true, the comment is private, otherwise it is
                      assumed to be public.
work_time    double   Adds this many hours to the "Hours Worked" on the bug.
                      If you are not in the time tracking group, this value will
                      be ignored.
===========  =======  ===========================================================

**Response**

.. code-block:: js

   {
     "id" : 789
   }

====  ====  =================================
name  type  description
====  ====  =================================
id    int   ID of the newly-created comment.
====  ====  =================================

**Errors**

* 54 (Hours Worked Too Large)
  You specified a "work_time" larger than the maximum allowed value of
  "99999.99".
* 100 (Invalid Bug Alias)
  If you specified an alias and there is no bug with that alias.
* 101 (Invalid Bug ID)
  The id you specified doesn't exist in the database.
* 109 (Bug Edit Denied)
  You did not have the necessary rights to edit the bug.
* 113 (Can't Make Private Comments)
  You tried to add a private comment, but don't have the necessary rights.
* 114 (Comment Too Long)
  You tried to add a comment longer than the maximum allowed length
  (65,535 characters).
* 140 (Markdown Disabled)
  You tried to set the "is_markdown" flag to true but the Markdown feature
  is not enabled.

.. _rest_search_comment_tags:

Search Comment Tags
-------------------

Searches for tags which contain the provided substring.

**Request**

To search for comment tags:

.. code-block:: text

   GET /rest/bug/comment/tags/(query)

Example:

.. code-block:: text

   GET /rest/bug/comment/tags/spa

=========  ======  ====================================================
name       type    description
=========  ======  ====================================================
**query**  string  Only tags containg this substring will be returned.
limit      int     If provided will return no more than ``limit`` tags.
                   Defaults to ``10``.
=========  ======  ====================================================

**Response**

.. code-block:: js

   [
     "spam"
   ]

An array of matching tags.

**Errors**

This method can throw all of the errors that :ref:`rest_single_bug` throws, plus:

* 125 (Comment Tagging Disabled)
  Comment tagging support is not available or enabled.

.. _rest_update_comment_tags:

Update Comment Tags
-------------------

Adds or removes tags from a comment.

**Request**

To update the tags comments attached to a comment:

.. code-block:: text

   PUT /rest/bug/comment/(comment_id)/tags

Example:

.. code-block:: js

   {
     "comment_id" : 75,
     "add" : ["spam", "bad"]
   }

==============  =====  ====================================
name            type   description
==============  =====  ====================================
**comment_id**  int    The ID of the comment to update.
add             array  The tags to attach to the comment.
remove          array  The tags to detach from the comment.
==============  =====  ====================================

**Response**

.. code-block:: js

   [
     "bad",
     "spam"
   ]

An array of strings containing the comment's updated tags.

**Errors**

This method can throw all of the errors that :ref:`rest_single_bug` throws, plus:

* 125 (Comment Tagging Disabled)
  Comment tagging support is not available or enabled.
* 126 (Invalid Comment Tag)
  The comment tag provided was not valid (eg. contains invalid characters).
* 127 (Comment Tag Too Short)
  The comment tag provided is shorter than the minimum length.
* 128 (Comment Tag Too Long)
  The comment tag provided is longer than the maximum length.

.. _rest_render_comment:

Render Comment
--------------

Returns the HTML rendering of the provided comment text.

**Request**

.. code-block:: text

   POST /rest/bug/comment/render

Example:

.. code-block:: js

   {
     "id" : 2345,
     "text" : "This issue has been fixed in bug 1234."
   }

==============  ======  ================================================
name            type    description
==============  ======  ================================================
**text**        string  Comment text to render.
id              int     The ID of the bug to render the comment against.
==============  ======  ================================================

**Response**

.. code-block:: js

   {
     "html" : "This issue has been fixed in <a class=\"bz_bug_link
          bz_status_RESOLVED  bz_closed\" title=\"RESOLVED FIXED - some issue that was fixed\" href=\"show_bug.cgi?id=1234\">bug 1234</a>."
   ]

====  ======  ===================================
name  type    description
====  ======  ===================================
html  string  Text containing the HTML rendering.
====  ======  ===================================

**Errors**

This method can throw all of the errors that :ref:`rest_single_bug` throws.
