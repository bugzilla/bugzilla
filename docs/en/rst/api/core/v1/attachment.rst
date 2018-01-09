Attachments
===========

The Bugzilla API for creating, changing, and getting the details of attachments.

.. _rest_attachments:

Get Attachment
--------------

This allows you to get data about attachments, given a list of bugs and/or
attachment IDs. Private attachments will only be returned if you are in the
appropriate group or if you are the submitter of the attachment.

**Request**

To get all current attachments for a bug:

.. code-block:: text

   GET /rest/bug/(bug_id)/attachment

To get a specific attachment based on attachment ID:

.. code-block:: text

   GET /rest/bug/attachment/(attachment_id)

One of the below must be specified.

=================  ====  ======================================================
name               type  description
=================  ====  ======================================================
**bug_id**         int   Integer bug ID.
**attachment_id**  int   Integer attachment ID.
=================  ====  ======================================================

**Response**

.. code-block:: js

   {
      "bugs" : {
         "1345" : [
            { (attachment) },
            { (attachment) }
         ],
         "9874" : [
            { (attachment) },
            { (attachment) }
         ],
      },
      "attachments" : {
         "234" : { (attachment) },
         "123" : { (attachment) },
      }
   }

An object containing two elements: ``bugs`` and ``attachments``.

The attachments for the bug that you specified in the ``bug_id`` argument in
input are returned in ``bugs`` on output. ``bugs`` is a object that has integer
bug IDs for keys and the values are arrays of objects as attachments.
(Fields for attachments are described below.)

For the attachment that you specified directly in ``attachment_id``, they
are returned in ``attachments`` on output. This is a object where the attachment
ids point directly to objects describing the individual attachment.

The fields for each attachment (where it says ``(attachment)`` in the
sample response above) are:

================  ========  =====================================================
name              type      description
================  ========  =====================================================
data              base64    The raw data of the attachment, encoded as Base64.
size              int       The length (in bytes) of the attachment.
creation_time     datetime  The time the attachment was created.
last_change_time  datetime  The last time the attachment was modified.
id                int       The numeric ID of the attachment.
bug_id            int       The numeric ID of the bug that the attachment is
                            attached to.
file_name         string    The file name of the attachment.
summary           string    A short string describing the attachment.
content_type      string    The MIME type of the attachment.
is_private        boolean   ``true`` if the attachment is private (only visible
                            to a certain group called the "insidergroup",
                            ``false`` otherwise.
is_obsolete       boolean   ``true`` if the attachment is obsolete, ``false``
                            otherwise.
is_patch          boolean   ``true`` if the attachment is a patch, ``false``
                            otherwise.
creator           string    The login name of the user that created the
                            attachment.
flags             array     Array of objects, each containing the information
                            about the flag currently set for each attachment.
                            Each flag object contains items described in the
                            Flag object below.
================  ========  =====================================================

Flag object:

=================  ========  ====================================================
name               type      description
=================  ========  ====================================================
id                 int       The ID of the flag.
name               string    The name of the flag.
type_id            int       The type ID of the flag.
creation_date      datetime  The timestamp when this flag was originally created.
modification_date  datetime  The timestamp when the flag was last modified.
status             string    The current status of the flag such as ?, +, or -.
setter             string    The login name of the user who created or last
                             modified the flag.
requestee          string    The login name of the user this flag has been
                             requested to be granted or denied. Note, this field
                             is only returned if a requestee is set.
=================  ========  ====================================================

**Errors**

This method can throw all the same errors as :ref:`rest_single_bug`. In addition,
it can also throw the following error:

* 304 (Auth Failure, Attachment is Private)
  You specified the id of a private attachment in the "attachment_ids"
  argument, and you are not in the "insider group" that can see
  private attachments.

.. _rest_add_attachment:

Create Attachment
-----------------

This allows you to add an attachment to a bug in Bugzilla.

**Request**

To create attachment on a current bug:

.. code-block:: text

   POST /rest/bug/(bug_id)/attachment

.. code-block:: js

   {
     "ids" : [ 35 ],
     "is_patch" : true,
     "comment" : "This is a new attachment comment",
     "is_markdown" : true,
     "summary" : "Test Attachment",
     "content_type" : "text/plain",
     "data" : "(Some base64 encoded content)",
     "file_name" : "test_attachment.patch",
     "obsoletes" : [],
     "is_private" : false,
     "flags" : [
       {
         "name" : "review",
         "status" : "?",
         "requestee" : "user@bugzilla.org",
         "new" : true
       }
     ]
   }


The params to include in the POST body, as well as the returned
data format, are the same as below. The ``bug_id`` param will be
overridden as it it pulled from the URL path.

================  =======  ======================================================
name              type     description
================  =======  ======================================================
**ids**           array    The IDs or aliases of bugs that you want to add this
                           attachment to. The same attachment and comment will be
                           added to all these bugs.
**data**          base64   The content of the attachment. You must encode it in
                           base64 using an appropriate client library such as
                           ``MIME::Base64`` for Perl.
**file_name**     string   The "file name" that will be displayed in the UI for
                           this attachment and also downloaded copies will be
                           given.
**summary**       string   A short string describing the attachment.
**content_type**  string   The MIME type of the attachment, like ``text/plain``
                           or ``image/png``.
comment           string   A comment to add along with this attachment.
is_patch          boolean  ``true`` if Bugzilla should treat this attachment as a
                           patch. If you specify this, you do not need to specify
                           a ``content_type``. The ``content_type`` of the
                           attachment will be forced to ``text/plain``. Defaults
                           to ``false`` if not specified.
is_private        boolean  ``true`` if the attachment should be private
                           (restricted to the "insidergroup"), ``false`` if the
                           attachment should be public. Defaults to ``false`` if
                           not specified.
is_markdown       boolean  If set to ``true``, the comment has Markdown structures;
                           otherwise, it is normal text.
flags             array    Flags objects to add to the attachment. The object
                           format is described in the Flag object below.
================  =======  ======================================================

Flag object:

To create a flag, at least the ``status`` and the ``type_id`` or ``name`` must
be provided. An optional requestee can be passed if the flag type is requestable
to a specific user.

=========  ======  ==============================================================
name       type    description
=========  ======  ==============================================================
name       string  The name of the flag type.
type_id    int     The internal flag type ID.
status     string  The flags new status (i.e. "?", "+", "-" or "X" to clear a
                   flag).
requestee  string  The login of the requestee if the flag type is requestable to
                   a specific user.
=========  ======  ==============================================================

**Response**

.. code-block:: js

   {
     "ids" : [
       "2797"
     ]
   }

====  =====  =========================
name  type   description
====  =====  =========================
ids   array  Attachment IDs created.
====  =====  =========================

**Errors**

This method can throw all the same errors as :ref:`rest_single_bug`, plus:

* 129 (Flag Status Invalid)
  The flag status is invalid.
* 130 (Flag Modification Denied)
  You tried to request, grant, or deny a flag but only a user with the required
  permissions may make the change.
* 131 (Flag not Requestable from Specific Person)
  You can't ask a specific person for the flag.
* 133 (Flag Type not Unique)
  The flag type specified matches several flag types. You must specify
  the type id value to update or add a flag.
* 134 (Inactive Flag Type)
  The flag type is inactive and cannot be used to create new flags.
* 140 (Markdown Disabled)
  You tried to set the "is_markdown" flag of the comment to true but the Markdown feature is not enabled.
* 600 (Attachment Too Large)
  You tried to attach a file that was larger than Bugzilla will accept.
* 601 (Invalid MIME Type)
  You specified a "content_type" argument that was blank, not a valid
  MIME type, or not a MIME type that Bugzilla accepts for attachments.
* 603 (File Name Not Specified)
  You did not specify a valid for the "file_name" argument.
* 604 (Summary Required)
  You did not specify a value for the "summary" argument.
* 606 (Empty Data)
  You set the "data" field to an empty string.

.. _rest_update_attachment:

Update Attachment
-----------------

This allows you to update attachment metadata in Bugzilla.

**Request**

To update attachment metadata on a current attachment:

.. code-block:: text

   PUT /rest/bug/attachment/(attachment_id)

.. code-block:: js

   {
     "ids" : [ 2796 ],
     "summary" : "Test XML file",
     "comment" : "Changed this from a patch to a XML file",
     "is_markdown" : true,
     "content_type" : "text/xml",
     "is_patch" : 0
   }

=================  =====  =======================================================
name               type   description
=================  =====  =======================================================
**attachment_id**  int    Integer attachment ID.
**ids**            array  The IDs of the attachments you want to update.
=================  =====  =======================================================

============  =======  ==========================================================
name          type     description
============  =======  ==========================================================
file_name     string   The "file name" that will be displayed in the UI for this
                       attachment.
summary       string   A short string describing the attachment.
comment       string   An optional comment to add to the attachment's bug.
is_markdown   boolean  If set to ``true``, the comment has Markdown structures;
                       otherwise, it is normal text.
content_type  string   The MIME type of the attachment, like ``text/plain``
                       or ``image/png``.
is_patch      boolean  ``true`` if Bugzilla should treat this attachment as a
                       patch. If you specify this, you do not need to specify a
                       ``content_type``. The ``content_type`` of the attachment
                       will be forced to ``text/plain``.
is_private    boolean  ``true`` if the attachment should be private (restricted
                       to the "insidergroup"), ``false`` if the attachment
                       should be public.
is_obsolete   boolean  ``true`` if the attachment is obsolete, ``false``
                       otherwise.
flags         array    An array of Flag objects with changes to the flags. The
                       object format is described in the Flag object below.
============  =======  ==========================================================

Flag object:

The following values can be specified. At least the ``status`` and one of
``type_id``, ``id``, or ``name`` must be specified. If a type_id or name matches
a single currently set flag, the flag will be updated unless ``new`` is specified.

=========  =======  =============================================================
name       type     description
=========  =======  =============================================================
name       string   The name of the flag that will be created or updated.
type_id    int      The internal flag type ID that will be created or updated.
                    You will need to specify the ``type_id`` if more than one
                    flag type of the same name exists.
status     string   The flags new status (i.e. "?", "+", "-" or "X" to clear a
                    flag).
requestee  string   The login of the requestee if the flag type is requestable
                    to a specific user.
id         int      Use ID to specify the flag to be updated. You will need to
                    specify the ``id`` if more than one flag is set of the same
                    name.
new        boolean  Set to true if you specifically want a new flag to be
                    created.
=========  =======  =============================================================

**Response**

.. code-block:: js

   {
     "attachments" : [
       {
         "changes" : {
           "content_type" : {
             "added" : "text/xml",
             "removed" : "text/plain"
           },
           "is_patch" : {
             "added" : "0",
             "removed" : "1"
           },
           "summary" : {
             "added" : "Test XML file",
             "removed" : "test patch"
           }
         },
         "id" : 2796,
         "last_change_time" : "2014-09-29T14:41:53Z"
       }
     ]
   }

``attachments`` (array) Change objects with the following items:

================  ========  =====================================================
name              type      description
================  ========  =====================================================
id                int       The ID of the attachment that was updated.
last_change_time  datetime  The exact time that this update was done at, for this
                            attachment. If no update was done (that is, no fields
                            had their values changed and no comment was added)
                            then this will instead be the last time the
                            attachment was updated.
changes           object    The changes that were actually done on this
                            attachment. The keys are the names of the fields that
                            were changed, and the values are an object with two
                            items:

                            * added: (string) The values that were added to this
                              field. Possibly a comma-and-space-separated list
                              if multiple values were added.
                            * removed: (string) The values that were removed from
                              this field.
================  ========  =====================================================

**Errors**

This method can throw all the same errors as :ref:`rest_single_bug`, plus:

* 129 (Flag Status Invalid)
  The flag status is invalid.
* 130 (Flag Modification Denied)
  You tried to request, grant, or deny a flag but only a user with the required
  permissions may make the change.
* 131 (Flag not Requestable from Specific Person)
  You can't ask a specific person for the flag.
* 132 (Flag not Unique)
  The flag specified has been set multiple times. You must specify the id
  value to update the flag.
* 133 (Flag Type not Unique)
  The flag type specified matches several flag types. You must specify
  the type id value to update or add a flag.
* 134 (Inactive Flag Type)
  The flag type is inactive and cannot be used to create new flags.
* 140 (Markdown Disabled)
  You tried to set the "is_markdown" flag of the "comment" to true but Markdown feature is
  not enabled.
* 601 (Invalid MIME Type)
  You specified a "content_type" argument that was blank, not a valid
  MIME type, or not a MIME type that Bugzilla accepts for attachments.
* 603 (File Name Not Specified)
  You did not specify a valid for the "file_name" argument.
* 604 (Summary Required)
  You did not specify a value for the "summary" argument.
