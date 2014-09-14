.. _administering:

======================
Administering Bugzilla
======================

.. toctree::
   :maxdepth: 2

   administering/parameters
   administering/preferences
   administering/users
   administering/categorization
   administering/flags
   administering/fields
   administering/workflow
   administering/groups
   administering/keywords
   administering/whining
   administering/extensions

.. _voting:

Voting
######

All of the code for voting in Bugzilla has been moved into an
extension, called "Voting", in the :file:`extensions/Voting/`
directory. To enable it, you must remove the :file:`disabled`
file from that directory, and run :file:`checksetup.pl`.

Voting allows users to be given a pot of votes which they can allocate
to bugs, to indicate that they'd like them fixed.
This allows developers to gauge
user need for a particular enhancement or bugfix. By allowing bugs with
a certain number of votes to automatically move from "UNCONFIRMED" to
"CONFIRMED", users of the bug system can help high-priority bugs garner
attention so they don't sit for a long time awaiting triage.

To modify Voting settings:

#. Navigate to the "Edit product" screen for the Product you
   wish to modify

#. *Maximum Votes per person*:
   Setting this field to "0" disables voting.

#. *Maximum Votes a person can put on a single
   bug*:
   It should probably be some number lower than the
   "Maximum votes per person". Don't set this field to "0" if
   "Maximum votes per person" is non-zero; that doesn't make
   any sense.

#. *Number of votes a bug in this product needs to
   automatically get out of the UNCONFIRMED state*:
   Setting this field to "0" disables the automatic move of
   bugs from UNCONFIRMED to CONFIRMED.

#. Once you have adjusted the values to your preference, click
   "Update".

.. _quips:

Quips
#####

Quips are small text messages that can be configured to appear
next to search results. A Bugzilla installation can have its own specific
quips. Whenever a quip needs to be displayed, a random selection
is made from the pool of already existing quips.

Quip submission is controlled by the *quip_list_entry_control*
parameter.  It has several possible values: open, moderated, or closed.
In order to enable quips approval you need to set this parameter to
"moderated". In this way, users are free to submit quips for addition
but an administrator must explicitly approve them before they are
actually used.

In order to see the user interface for the quips, it is enough to click
on a quip when it is displayed together with the search results. Or
it can be seen directly in the browser by visiting the quips.cgi URL
(prefixed with the usual web location of the Bugzilla installation).
Once the quip interface is displayed, it is enough to click the
"view and edit the whole quip list" in order to see the administration
page. A page with all the quips available in the database will
be displayed.

Next to each quip there is a checkbox, under the
"Approved" column. Quips who have this checkbox checked are
already approved and will appear next to the search results.
The ones that have it unchecked are still preserved in the
database but they will not appear on search results pages.
User submitted quips have initially the checkbox unchecked.

Also, there is a delete link next to each quip,
which can be used in order to permanently delete a quip.

Display of quips is controlled by the *display_quips*
user preference.  Possible values are "on" and "off".

