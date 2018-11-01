Flag Activity
=============

This API provides information about activity relating to bug and attachment flags.

Get Flag Activity
-----------------

**Request**

There are a variety of methods for querying flag activity based on different criteria.

.. code-block:: text

   GET /rest/review/flag_activity/(flag_id)

Fetches activity for the given flag as specified by its id.

.. code-block:: text

   GET /rest/review/flag_activity/requestee/(requestee)

Fetches activity for flags where the requestee matches the given Bugzilla login.

.. code-block:: text

   GET /rest/review/flag_activity/setter/(requestee)

Fetches activity for flags where the setter matches the given Bugzilla login.

.. code-block:: text

   GET /rest/review/flag_activity/type_id/(type_id)

Fetches activity for all flags of the type specified by its id.

.. code-block:: text

   GET /rest/review/flag_activity/type_name/(type_name)

Fetches activity for all flags of the type specified by its name.

.. code-block:: text

   GET /rest/review/flag_activity

Fetches activity for all flags.

There are also query parameters that can be used to further filter the response:

======  ======  ===================================================
name    type    description
======  ======  ===================================================
limit   int     Number of entries to return.
offset  int     Number of entries to skip before returning results.
after   date    Display activity occurring on or after this date.
before  date    Display activity occurring before this date.
======  ======  ===================================================

Note that if ``offset`` is specified, ``limit`` must be given as well.

There is a site-specific maximum number of entries that will be returned regardless of
the value given for ``limit``.  This is also the default if ``limit`` is not specified.

For example, to get the first 100 flag-activity entries that occurred on or after
2018-01-01 for flag ID 42:

.. code-block:: text

    GET /rest/review/flag_activity/42?limit=100&after=2018-01-01

**Response**

.. code-block:: js

   [
     {
       "attachment_id": null,
       "bug_id": 1395127,
       "creation_time": "2018-10-10 12:41:00",
       "flag_id": 1637223,
       "id": 1449303,
       "requestee": {
         "id": 123,
         "name": "user@mozilla.com",
         "real_name": "J. Random User"
       },
       "setter": {
         "id": 123,
         "name": "user@mozilla.com",
         "real_name": "J. Random User"
       },
       "status": "?",
       "type": {
         "description": "Set this flag when the bug is in need of additional information.",
         "id": 800,
         "is_active": true,
         "is_multiplicable": true,
         "is_requesteeble": true,
         "name": "needinfo",
         "type": "bug"
       }
     }
   ]

An object containing a list of flags.  The fields for each flag are as follows:

=============  ========  ====================================================
name           type      description
=============  ========  ====================================================
attachment_id  int       The numeric ID of the associated attachment, if any.
bug_id         int       The numeric ID of the associated bug.
creation_time  datetime  The time the flag status changed.
flag_id        int       The numeric ID of this flag instance.
id             int       The numeric ID of this flag-activity event.
requestee      object    Data about the user of which the flag was requested.
setter         object    Data about the user who set the flag.
status         string    Status of the flag: "?", "+", or "-".
type           object    Data about the type of flag.
=============  ========  ====================================================

The requestee and setter objects have the following fields:

=========  ======  ====================================================
name       type    description
=========  ======  ====================================================
id         int     The unique ID of the user.
name       string  The login of the user (typically an email address).
real_name  string  The real name of the user, if set.
=========  ======  ====================================================

The type object has the following fields:

================  =======  =============================================================================
name              type     description
================  =======  =============================================================================
description       string   A plain-English description of the flag type.
id                int      The numeric ID of the flag type.
is_active         boolean  Indicates if the flag type can be used.
is_multiplicable  boolean  Indicates if more than one flags of this type can be set on a bug/attachment.
is_requesteeble   boolean  Indicates if this flag type supports a requestee.
name              string   Short descriptive name of this flag type.
type              string   The object to which this flag type can be applied (e.g. "bug", "attachment").
================  =======  =============================================================================

**Errors**

If a nonexistent but properly specified (i.e. integer value) flag or flag-type ID is given, a 200 OK
response will be returned with an empty array.  In other cases, different response codes may be
returned:

* 400 (Bad Request): An invalid flag or flag-type ID was given, or ``offset`` was given without a
  value for ``limit``.
