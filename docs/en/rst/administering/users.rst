.. _users:

Users
#####

.. _defaultuser:

Creating Admin Users
====================

When you first run checksetup.pl after installing Bugzilla, it will
prompt you for the username (email address) and password for the first
admin user. If for some reason you delete all the admin users,
re-running checksetup.pl will again prompt you for a username and
password and make a new admin.

If you wish to add more administrative users, add them to the "admin" group.

.. _user-account-search:

Searching For Users
===================

If you have ``editusers`` privileges or if you are allowed
to grant privileges for some groups, the :guilabel:`Users` link
will appear in the Administration page.

The first screen is a search form to search for existing user
accounts. You can run searches based either on the user ID, real
name or login name (i.e. the email address, or just the first part
of the email address if the :param:`emailsuffix` parameter is set).
The search can be conducted
in different ways using the listbox to the right of the text entry
box. You can match by case-insensitive substring (the default),
regular expression, a *reverse* regular expression
match (which finds every user name which does NOT match the regular
expression), or the exact string if you know exactly who you are
looking for. The search can be restricted to users who are in a
specific group. By default, the restriction is turned off.

The search returns a list of
users matching your criteria. User properties can be edited by clicking
the login name. The Account History of a user can be viewed by clicking
the "View" link in the Account History column. The Account History
displays changes that have been made to the user account, the time of
the change and the user who made the change. For example, the Account
History page will display details of when a user was added or removed
from a group.

.. _modifyusers:

Modifying Users
===============

Once you have found your user, you can change the following
fields:

- *Login Name*:
  This is generally the user's full email address. However, if you
  have are using the :param:`emailsuffix` parameter, this may
  just be the user's login name. Unless you turn off the
  :param:`allowemailchange` parameter, users can change their
  email address to any other valid email address they control.

- *Real Name*: The user's real name. Note that
  Bugzilla does not require this to create an account.

- *Password*:
  You can change the user's password here. Users can automatically
  request a new password, so you shouldn't need to do this often.
  If you want to disable an account, see Disable Text below.

- *Bugmail Disabled*:
  Check this checkbox to disable bugmail and whinemail completely
  for this account. Note that this does not prevent the user logging in or
  taking any other action.

- *Disable Text*:
  If you type anything in this box, including just a space, the
  user is prevented from logging in and from making any changes to
  bugs via the web interface.
  The HTML you type in this box is presented to the user when
  they attempt to perform these actions and should explain
  why the account was disabled.
  Users with disabled accounts will continue to receive
  mail from Bugzilla; furthermore, they will not be able
  to log in themselves to change their own preferences and
  stop it. If you want an account (disabled or active) to
  stop receiving mail, simply check the
  ``Bugmail Disabled`` checkbox above.

  .. note:: Even users whose accounts have been disabled can still
     submit bugs via the email gateway, if one exists.
     The email gateway should *not* be
     enabled for secure installations of Bugzilla.

  .. warning:: Don't disable all the administrator accounts!

- *<groupname>*:
  Checkboxes will appear here to allow you to add users to, or
  remove them from, permission groups. The first checkbox gives the
  user the ability to add and remove other users as members of
  this group. The second checkbox makes the user himself a member
  of the group.

  Bugzilla has a number of built-in groups. For the full set of groups and their
  capabilities, see :ref:`permissions`. This list will also contain any groups
  you have created.

.. _createnewusers:

Creating New Users
==================

.. _self-registration:

Self-Registration
-----------------

By default, users can create their own user accounts by clicking the
``New Account`` link at the bottom of each page (assuming
they aren't logged in as someone else already). If you want to disable
this self-registration, or if you want to restrict who can create their
own user account, you have to edit the :param:`createemailregexp`
parameter in the ``Configuration`` page; see
:ref:`parameters`.

.. _user-account-creation:

Administrator Registration
--------------------------

Users with ``editusers`` privileges, such as administrators,
can create user accounts for other users:

#. After logging in, click the "Users" link at the footer of
   the query page, and then click "Add a new user".

#. Fill out the form presented. This page is self-explanatory.
   When done, click "Submit".

   .. note:: Adding a user this way will *not*
      send an email informing them of their username and password.
      While useful for creating dummy accounts (watchers which
      shuttle mail to another system, for instance, or email
      addresses which are a mailing list), in general it is
      preferable to log out and use the ``New Account``
      button to create users, as it will pre-populate all the
      required fields and also notify the user of her account name
      and password.

.. _user-account-deletion:

Deleting Users
==============

If the :param:`allowuserdeletion` parameter is turned on (see
:ref:`parameters`) then you can also delete user accounts.
Note that, most of the time, this is not the best thing to do. If only
a warning in a yellow box is displayed, then the deletion is safe.
If a warning is also displayed in a red box, then you should NOT try
to delete the user account, else you will get referential integrity
problems in your database, which can lead to unexpected behavior,
such as bugs not appearing in bug lists anymore, or data displaying
incorrectly. You have been warned!

.. _impersonatingusers:

Impersonating Users
===================

There may be times when an administrator would like to do something as
another user.  The :command:`sudo` feature may be used to do
this.

.. note:: To use the sudo feature, you must be in the
   *bz_sudoers* group.  By default, all
   administrators are in this group.

If you have access to this feature, you may start a session by
going to the Edit Users page, Searching for a user and clicking on
their login.  You should see a link below their login name titled
"Impersonate this user".  Click on the link.  This will take you
to a page where you will see a description of the feature and
instructions for using it.  After reading the text, simply
enter the login of the user you would like to impersonate, provide
a short message explaining why you are doing this, and press the
button.

As long as you are using this feature, everything you do will be done
as if you were logged in as the user you are impersonating.

.. warning:: The user you are impersonating will not be told about what you are
   doing.  If you do anything that results in mail being sent, that
   mail will appear to be from the user you are impersonating.  You
   should be extremely careful while using this feature.

