

.. _administration:

======================
Administering Bugzilla
======================

.. _parameters:

Bugzilla Configuration
######################

Bugzilla is configured by changing various parameters, accessed
from the "Parameters" link in the Administration page (the
Administration page can be found by clicking the "Administration"
link in the footer). The parameters are divided into several categories,
accessed via the menu on the left. Following is a description of the
different categories and important parameters within those categories.

.. _param-requiredsettings:

Required Settings
=================

The core required parameters for any Bugzilla installation are set
here. These parameters must be set before a new Bugzilla installation
can be used. Administrators should review this list before
deploying a new Bugzilla installation.

maintainer
    Email address of the person
    responsible for maintaining this Bugzilla installation.
    The address need not be that of a valid Bugzilla account.

urlbase
    Defines the fully qualified domain name and web
    server path to this Bugzilla installation.
    For example, if the Bugzilla query page is
    :file:`http://www.foo.com/bugzilla/query.cgi`,
    the ``urlbase`` should be set
    to :file:`http://www.foo.com/bugzilla/`.

docs_urlbase
    Defines path to the Bugzilla documentation. This can be a fully
    qualified domain name, or a path relative to "urlbase".
    For example, if the "Bugzilla Configuration" page
    of the documentation is
    :file:`http://www.foo.com/bugzilla/docs/html/parameters.html`,
    set the ``docs_urlbase``
    to :file:`http://www.foo.com/bugzilla/docs/html/`.

sslbase
    Defines the fully qualified domain name and web
    server path for HTTPS (SSL) connections to this Bugzilla installation.
    For example, if the Bugzilla main page is
    :file:`https://www.foo.com/bugzilla/index.cgi`,
    the ``sslbase`` should be set
    to :file:`https://www.foo.com/bugzilla/`.

ssl_redirect
    If enabled, Bugzilla will force HTTPS (SSL) connections, by
    automatically redirecting any users who try to use a non-SSL
    connection.

cookiedomain
    Defines the domain for Bugzilla cookies. This is typically left blank.
    If there are multiple hostnames that point to the same webserver, which
    require the same cookie, then this parameter can be utilized. For
    example, If your website is at
    :file:`https://www.foo.com/`, setting this to
    :file:`.foo.com/` will also allow
    :file:`bar.foo.com/` to access Bugzilla cookies.

cookiepath
    Defines a path, relative to the web server root, that Bugzilla
    cookies will be restricted to. For example, if the
    :command:`urlbase` is set to
    :file:`http://www.foo.com/bugzilla/`, the
    :command:`cookiepath` should be set to
    :file:`/bugzilla/`. Setting it to "/" will allow all sites
    served by this web server or virtual host to read Bugzilla cookies.

utf8
    Determines whether to use UTF-8 (Unicode) encoding for all text in
    Bugzilla. New installations should set this to true to avoid character
    encoding problems. Existing databases should set this to true only
    after the data has been converted from existing legacy character
    encoding to UTF-8, using the
    :file:`contrib/recode.pl` script.

    .. note:: If you turn this parameter from "off" to "on", you must
       re-run :file:`checksetup.pl` immediately afterward.

shutdownhtml
    If there is any text in this field, this Bugzilla installation will
    be completely disabled and this text will appear instead of all
    Bugzilla pages for all users, including Admins. Used in the event
    of site maintenance or outage situations.

    .. note:: Although regular log-in capability is disabled
       while :command:`shutdownhtml`
       is enabled, safeguards are in place to protect the unfortunate
       admin who loses connection to Bugzilla. Should this happen to you,
       go directly to the :file:`editparams.cgi` (by typing
       the URL in manually, if necessary). Doing this will prompt you to
       log in, and your name/password will be accepted here (but nowhere
       else).

announcehtml
    Any text in this field will be displayed at the top of every HTML
    page in this Bugzilla installation. The text is not wrapped in any
    tags. For best results, wrap the text in a ``<div>``
    tag. Any style attributes from the CSS can be applied. For example,
    to make the text green inside of a red box, add ``id=message``
    to the ``<div>`` tag.

proxy_url
    If this Bugzilla installation is behind a proxy, enter the proxy
    information here to enable Bugzilla to access the Internet. Bugzilla
    requires Internet access to utilize the
    :command:`upgrade_notification` parameter (below). If the
    proxy requires authentication, use the syntax:
    :file:`http://user:pass@proxy_url/`.

upgrade_notification
    Enable or disable a notification on the homepage of this Bugzilla
    installation when a newer version of Bugzilla is available. This
    notification is only visible to administrators. Choose "disabled",
    to turn off the notification. Otherwise, choose which version of
    Bugzilla you want to be notified about: "development_snapshot" is the
    latest release on the trunk; "latest_stable_release" is the most
    recent release available on the most recent stable branch;
    "stable_branch_release" the most recent release on the branch
    this installation is based on.

.. _param-admin-policies:

Administrative Policies
=======================

This page contains parameters for basic administrative functions.
Options include whether to allow the deletion of bugs and users,
and whether to allow users to change their email address.

.. _param-user-authentication:

User Authentication
===================

This page contains the settings that control how this Bugzilla
installation will do its authentication. Choose what authentication
mechanism to use (the Bugzilla database, or an external source such
as LDAP), and set basic behavioral parameters. For example, choose
whether to require users to login to browse bugs, the management
of authentication cookies, and the regular expression used to
validate email addresses. Some parameters are highlighted below.

emailregexp
    Defines the regular expression used to validate email addresses
    used for login names. The default attempts to match fully
    qualified email addresses (i.e. 'user@example.com') in a slightly
    more restrictive way than what is allowed in RFC 2822.
    Some Bugzilla installations allow only local user names (i.e 'user'
    instead of 'user@example.com'). In that case, this parameter
    should be used to define the email domain.

emailsuffix
    This string is appended to login names when actually sending
    email to a user. For example,
    If :command:`emailregexp` has been set to allow
    local usernames,
    then this parameter would contain the email domain for all users
    (i.e. '@example.com').

.. _param-attachments:

Attachments
===========

This page allows for setting restrictions and other parameters
regarding attachments to bugs. For example, control size limitations
and whether to allow pointing to external files via a URI.

.. _param-bug-change-policies:

Bug Change Policies
===================

Set policy on default behavior for bug change events. For example,
choose which status to set a bug to when it is marked as a duplicate,
and choose whether to allow bug reporters to set the priority or
target milestone. Also allows for configuration of what changes
should require the user to make a comment, described below.

commenton*
    All these fields allow you to dictate what changes can pass
    without comment, and which must have a comment from the
    person who changed them.  Often, administrators will allow
    users to add themselves to the CC list, accept bugs, or
    change the Status Whiteboard without adding a comment as to
    their reasons for the change, yet require that most other
    changes come with an explanation.
    Set the "commenton" options according to your site policy. It
    is a wise idea to require comments when users resolve, reassign, or
    reopen bugs at the very least.

    .. note:: It is generally far better to require a developer comment
       when resolving bugs than not. Few things are more annoying to bug
       database users than having a developer mark a bug "fixed" without
       any comment as to what the fix was (or even that it was truly
       fixed!)

noresolveonopenblockers
    This option will prevent users from resolving bugs as FIXED if
    they have unresolved dependencies. Only the FIXED resolution
    is affected. Users will be still able to resolve bugs to
    resolutions other than FIXED if they have unresolved dependent
    bugs.

.. _param-bugfields:

Bug Fields
==========

The parameters in this section determine the default settings of
several Bugzilla fields for new bugs, and also control whether
certain fields are used. For example, choose whether to use the
"target milestone" field or the "status whiteboard" field.

useqacontact
    This allows you to define an email address for each component,
    in addition to that of the default assignee, who will be sent
    carbon copies of incoming bugs.

usestatuswhiteboard
    This defines whether you wish to have a free-form, overwritable field
    associated with each bug. The advantage of the Status Whiteboard is
    that it can be deleted or modified with ease, and provides an
    easily-searchable field for indexing some bugs that have some trait
    in common.

.. _param-bugmoving:

Bug Moving
==========

This page controls whether this Bugzilla installation allows certain
users to move bugs to an external database. If bug moving is enabled,
there are a number of parameters that control bug moving behaviors.
For example, choose which users are allowed to move bugs, the location
of the external database, and the default product and component that
bugs moved *from* other bug databases to this
Bugzilla installation are assigned to.

.. _param-dependency-graphs:

Dependency Graphs
=================

This page has one parameter that sets the location of a Web Dot
server, or of the Web Dot binary on the local system, that is used
to generate dependency graphs. Web Dot is a CGI program that creates
images from :file:`.dot` graphic description files. If
no Web Dot server or binary is specified, then dependency graphs will
be disabled.

.. _param-group-security:

Group Security
==============

Bugzilla allows for the creation of different groups, with the
ability to restrict the visibility of bugs in a group to a set of
specific users. Specific products can also be associated with
groups, and users restricted to only see products in their groups.
Several parameters are described in more detail below. Most of the
configuration of groups and their relationship to products is done
on the "Groups" and "Product" pages of the "Administration" area.
The options on this page control global default behavior.
For more information on Groups and Group Security, see
:ref:`groups`

makeproductgroups
    Determines whether or not to automatically create groups
    when new products are created. If this is on, the groups will be
    used for querying bugs.

usevisibilitygroups
    If selected, user visibility will be restricted to members of
    groups, as selected in the group configuration settings.
    Each user-defined group can be allowed to see members of selected
    other groups.
    For details on configuring groups (including the visibility
    restrictions) see :ref:`edit-groups`.

querysharegroup
    The name of the group of users who are allowed to share saved
    searches with one another. For more information on using
    saved searches, see :ref:`savedsearches`.

.. _bzldap:

LDAP Authentication
===================

LDAP authentication is a module for Bugzilla's plugin
authentication architecture. This page contains all the parameters
necessary to configure Bugzilla for use with LDAP authentication.

The existing authentication
scheme for Bugzilla uses email addresses as the primary user ID, and a
password to authenticate that user. All places within Bugzilla that
require a user ID (e.g assigning a bug) use the email
address. The LDAP authentication builds on top of this scheme, rather
than replacing it. The initial log-in is done with a username and
password for the LDAP directory. Bugzilla tries to bind to LDAP using
those credentials and, if successful, tries to map this account to a
Bugzilla account. If an LDAP mail attribute is defined, the value of this
attribute is used, otherwise the "emailsuffix" parameter is appended to LDAP
username to form a full email address. If an account for this address
already exists in the Bugzilla installation, it will log in to that account.
If no account for that email address exists, one is created at the time
of login. (In this case, Bugzilla will attempt to use the "displayName"
or "cn" attribute to determine the user's full name.) After
authentication, all other user-related tasks are still handled by email
address, not LDAP username. For example, bugs are still assigned by
email address and users are still queried by email address.

.. warning:: Because the Bugzilla account is not created until the first time
   a user logs in, a user who has not yet logged is unknown to Bugzilla.
   This means they cannot be used as an assignee or QA contact (default or
   otherwise), added to any CC list, or any other such operation. One
   possible workaround is the :file:`bugzilla_ldapsync.rb`
   script in the :file:`contrib`
   directory. Another possible solution is fixing
   `bug
   201069 <https://bugzilla.mozilla.org/show_bug.cgi?id=201069>`_.

Parameters required to use LDAP Authentication:

user_verify_class
    If you want to list ``LDAP`` here,
    make sure to have set up the other parameters listed below.
    Unless you have other (working) authentication methods listed as
    well, you may otherwise not be able to log back in to Bugzilla once
    you log out.
    If this happens to you, you will need to manually edit
    :file:`data/params.json` and set user_verify_class to
    ``DB``.

LDAPserver
    This parameter should be set to the name (and optionally the
    port) of your LDAP server. If no port is specified, it assumes
    the default LDAP port of 389.
    For example: ``ldap.company.com``
    or ``ldap.company.com:3268``
    You can also specify a LDAP URI, so as to use other
    protocols, such as LDAPS or LDAPI. If port was not specified in
    the URI, the default is either 389 or 636 for 'LDAP' and 'LDAPS'
    schemes respectively.

    .. note:: In order to use SSL with LDAP, specify a URI with "ldaps://".
       This will force the use of SSL over port 636.
       For example, normal LDAP:
       ``ldap://ldap.company.com``, LDAP over SSL:
       ``ldaps://ldap.company.com`` or LDAP over a UNIX
       domain socket ``ldapi://%2fvar%2flib%2fldap_sock``.

LDAPbinddn \[Optional]
    Some LDAP servers will not allow an anonymous bind to search
    the directory. If this is the case with your configuration you
    should set the LDAPbinddn parameter to the user account Bugzilla
    should use instead of the anonymous bind.
    Ex. ``cn=default,cn=user:password``

LDAPBaseDN
    The LDAPBaseDN parameter should be set to the location in
    your LDAP tree that you would like to search for email addresses.
    Your uids should be unique under the DN specified here.
    Ex. ``ou=People,o=Company``

LDAPuidattribute
    The LDAPuidattribute parameter should be set to the attribute
    which contains the unique UID of your users. The value retrieved
    from this attribute will be used when attempting to bind as the
    user to confirm their password.
    Ex. ``uid``

LDAPmailattribute
    The LDAPmailattribute parameter should be the name of the
    attribute which contains the email address your users will enter
    into the Bugzilla login boxes.
    Ex. ``mail``

.. _bzradius:

RADIUS Authentication
=====================

RADIUS authentication is a module for Bugzilla's plugin
authentication architecture. This page contains all the parameters
necessary for configuring Bugzilla to use RADIUS authentication.

.. note:: Most caveats that apply to LDAP authentication apply to RADIUS
   authentication as well. See :ref:`bzldap` for details.

Parameters required to use RADIUS Authentication:

user_verify_class
    If you want to list ``RADIUS`` here,
    make sure to have set up the other parameters listed below.
    Unless you have other (working) authentication methods listed as
    well, you may otherwise not be able to log back in to Bugzilla once
    you log out.
    If this happens to you, you will need to manually edit
    :file:`data/params.json` and set user_verify_class to
    ``DB``.

RADIUS_server
    This parameter should be set to the name (and optionally the
    port) of your RADIUS server.

RADIUS_secret
    This parameter should be set to the RADIUS server's secret.

RADIUS_email_suffix
    Bugzilla needs an e-mail address for each user account.
    Therefore, it needs to determine the e-mail address corresponding
    to a RADIUS user.
    Bugzilla offers only a simple way to do this: it can concatenate
    a suffix to the RADIUS user name to convert it into an e-mail
    address.
    You can specify this suffix in the RADIUS_email_suffix parameter.
    If this simple solution does not work for you, you'll
    probably need to modify
    :file:`Bugzilla/Auth/Verify/RADIUS.pm` to match your
    requirements.

.. _param-email:

Email
=====

This page contains all of the parameters for configuring how
Bugzilla deals with the email notifications it sends. See below
for a summary of important options.

mail_delivery_method
    This is used to specify how email is sent, or if it is sent at
    all.  There are several options included for different MTAs,
    along with two additional options that disable email sending.
    "Test" does not send mail, but instead saves it in
    :file:`data/mailer.testfile` for later review.
    "None" disables email sending entirely.

mailfrom
    This is the email address that will appear in the "From" field
    of all emails sent by this Bugzilla installation. Some email
    servers require mail to be from a valid email address, therefore
    it is recommended to choose a valid email address here.

smtpserver
    This is the SMTP server address, if the ``mail_delivery_method``
    parameter is set to SMTP.  Use "localhost" if you have a local MTA
    running, otherwise use a remote SMTP server.  Append ":" and the port
    number, if a non-default port is needed.

smtp_username
    Username to use for SASL authentication to the SMTP server.  Leave
    this parameter empty if your server does not require authentication.

smtp_password
    Password to use for SASL authentication to the SMTP server. This
    parameter will be ignored if the ``smtp_username``
    parameter is left empty.

smtp_ssl
    Enable SSL support for connection to the SMTP server.

smtp_debug
    This parameter allows you to enable detailed debugging output.
    Log messages are printed the web server's error log.

whinedays
    Set this to the number of days you want to let bugs go
    in the CONFIRMED state before notifying people they have
    untouched new bugs. If you do not plan to use this feature, simply
    do not set up the whining cron job described in the installation
    instructions, or set this value to "0" (never whine).

globalwatcher
    This allows you to define specific users who will
    receive notification each time a new bug in entered, or when
    an existing bug changes, according to the normal groupset
    permissions. It may be useful for sending notifications to a
    mailing-list, for instance.

.. _param-patchviewer:

Patch Viewer
============

This page contains configuration parameters for the CVS server,
Bonsai server and LXR server that Bugzilla will use to enable the
features of the Patch Viewer. Bonsai is a tool that enables queries
to a CVS tree. LXR is a tool that can cross reference and index source
code.

.. _param-querydefaults:

Query Defaults
==============

This page controls the default behavior of Bugzilla in regards to
several aspects of querying bugs. Options include what the default
query options are, what the "My Bugs" page returns, whether users
can freely add bugs to the quip list, and how many duplicate bugs are
needed to add a bug to the "most frequently reported" list.

.. _param-shadowdatabase:

Shadow Database
===============

This page controls whether a shadow database is used, and all the
parameters associated with the shadow database. Versions of Bugzilla
prior to 3.2 used the MyISAM table type, which supports
only table-level write locking. With MyISAM, any time someone is making a change to
a bug, the entire table is locked until the write operation is complete.
Locking for write also blocks reads until the write is complete.

The ``shadowdb`` parameter was designed to get around
this limitation. While only a single user is allowed to write to
a table at a time, reads can continue unimpeded on a read-only
shadow copy of the database.

.. note:: As of version 3.2, Bugzilla no longer uses the MyISAM table type.
   Instead, InnoDB is used, which can do transaction-based locking.
   Therefore, the limitations the Shadow Database feature was designed
   to workaround no longer exist.

.. _admin-usermatching:

User Matching
=============

The settings on this page control how users are selected and queried
when adding a user to a bug. For example, users need to be selected
when choosing who the bug is assigned to, adding to the CC list or
selecting a QA contact. With the "usemenuforusers" parameter, it is
possible to configure Bugzilla to
display a list of users in the fields instead of an empty text field.
This should only be used in Bugzilla installations with a small number
of users. If users are selected via a text box, this page also
contains parameters for how user names can be queried and matched
when entered.

Another setting called 'ajax_user_autocompletion' enables certain
user fields to display a list of matched user names as a drop down after typing
a few characters. Note that it is recommended to use mod_perl when
enabling 'ajax_user_autocompletion'.

.. _useradmin:

User Administration
###################

.. _defaultuser:

Creating the Default User
=========================

When you first run checksetup.pl after installing Bugzilla, it
will prompt you for the administrative username (email address) and
password for this "super user". If for some reason you delete
the "super user" account, re-running checksetup.pl will again prompt
you for this username and password.

.. note:: If you wish to add more administrative users, add them to
   the "admin" group and, optionally, edit the tweakparams, editusers,
   creategroups, editcomponents, and editkeywords groups to add the
   entire admin group to those groups (which is the case by default).

.. _manageusers:

Managing Other Users
====================

.. _user-account-search:

Searching for existing users
----------------------------

If you have ``editusers`` privileges or if you are allowed
to grant privileges for some groups, the ``Users`` link
will appear in the Administration page.

The first screen is a search form to search for existing user
accounts. You can run searches based either on the user ID, real
name or login name (i.e. the email address, or just the first part
of the email address if the "emailsuffix" parameter is set).
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

.. _createnewusers:

Creating new users
------------------

.. _self-registration:

Self-registration
~~~~~~~~~~~~~~~~~

By default, users can create their own user accounts by clicking the
``New Account`` link at the bottom of each page (assuming
they aren't logged in as someone else already). If you want to disable
this self-registration, or if you want to restrict who can create his
own user account, you have to edit the ``createemailregexp``
parameter in the ``Configuration`` page, see
:ref:`parameters`.

.. _user-account-creation:

Accounts created by an administrator
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

.. _modifyusers:

Modifying Users
---------------

Once you have found your user, you can change the following
fields:

- *Login Name*:
  This is generally the user's full email address. However, if you
  have are using the ``emailsuffix`` parameter, this may
  just be the user's login name. Note that users can now change their
  login names themselves (to any valid email address).

- *Real Name*: The user's real name. Note that
  Bugzilla does not require this to create an account.

- *Password*:
  You can change the user's password here. Users can automatically
  request a new password, so you shouldn't need to do this often.
  If you want to disable an account, see Disable Text below.

- *Bugmail Disabled*:
  Mark this checkbox to disable bugmail and whinemail completely
  for this account. This checkbox replaces the data/nomail file
  which existed in older versions of Bugzilla.

- *Disable Text*:
  If you type anything in this box, including just a space, the
  user is prevented from logging in, or making any changes to
  bugs via the web interface.
  The HTML you type in this box is presented to the user when
  they attempt to perform these actions, and should explain
  why the account was disabled.
  Users with disabled accounts will continue to receive
  mail from Bugzilla; furthermore, they will not be able
  to log in themselves to change their own preferences and
  stop it. If you want an account (disabled or active) to
  stop receiving mail, simply check the
  ``Bugmail Disabled`` checkbox above.

  .. note:: Even users whose accounts have been disabled can still
     submit bugs via the e-mail gateway, if one exists.
     The e-mail gateway should *not* be
     enabled for secure installations of Bugzilla.

  .. warning:: Don't disable all the administrator accounts!

- *<groupname>*:
  If you have created some groups, e.g. "securitysensitive", then
  checkboxes will appear here to allow you to add users to, or
  remove them from, these groups. The first checkbox gives the
  user the ability to add and remove other users as members of
  this group. The second checkbox adds the user himself as a member
  of the group.

- *canconfirm*:
  This field is only used if you have enabled the "unconfirmed"
  status. If you enable this for a user,
  that user can then move bugs from "Unconfirmed" to a "Confirmed"
  status (e.g.: "New" status).

- *creategroups*:
  This option will allow a user to create and destroy groups in
  Bugzilla.

- *editbugs*:
  Unless a user has this bit set, they can only edit those bugs
  for which they are the assignee or the reporter. Even if this
  option is unchecked, users can still add comments to bugs.

- *editcomponents*:
  This flag allows a user to create new products and components,
  as well as modify and destroy those that have no bugs associated
  with them. If a product or component has bugs associated with it,
  those bugs must be moved to a different product or component
  before Bugzilla will allow them to be destroyed.

- *editkeywords*:
  If you use Bugzilla's keyword functionality, enabling this
  feature allows a user to create and destroy keywords. As always,
  the keywords for existing bugs containing the keyword the user
  wishes to destroy must be changed before Bugzilla will allow it
  to die.

- *editusers*:
  This flag allows a user to do what you're doing right now: edit
  other users. This will allow those with the right to do so to
  remove administrator privileges from other users or grant them to
  themselves. Enable with care.

- *tweakparams*:
  This flag allows a user to change Bugzilla's Params
  (using :file:`editparams.cgi`.)

- *<productname>*:
  This allows an administrator to specify the products
  in which a user can see bugs. If you turn on the
  ``makeproductgroups`` parameter in
  the Group Security Panel in the Parameters page,
  then Bugzilla creates one group per product (at the time you create
  the product), and this group has exactly the same name as the
  product itself. Note that for products that already exist when
  the parameter is turned on, the corresponding group will not be
  created. The user must still have the ``editbugs``
  privilege to edit bugs in these products.

.. _user-account-deletion:

Deleting Users
--------------

If the ``allowuserdeletion`` parameter is turned on, see
:ref:`parameters`, then you can also delete user accounts.
Note that this is most of the time not the best thing to do. If only
a warning in a yellow box is displayed, then the deletion is safe.
If a warning is also displayed in a red box, then you should NOT try
to delete the user account, else you will get referential integrity
problems in your database, which can lead to unexpected behavior,
such as bugs not appearing in bug lists anymore, or data displaying
incorrectly. You have been warned!

.. _impersonatingusers:

Impersonating Users
-------------------

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

.. _classifications:

Classifications
###############

Classifications tend to be used in order to group several related
products into one distinct entity.

The classifications layer is disabled by default; it can be turned
on or off using the useclassification parameter,
in the *Bug Fields* section of the edit parameters screen.

Access to the administration of classifications is controlled using
the *editclassifications* system group, which defines
a privilege for creating, destroying, and editing classifications.

When activated, classifications will introduce an additional
step when filling bugs (dedicated to classification selection), and they
will also appear in the advanced search form.

.. _products:

Products
########

Products typically represent real-world
shipping products. Products can be given
:ref:`classifications`.
For example, if a company makes computer games,
they could have a classification of "Games", and a separate
product for each game. This company might also have a
``Common`` product for units of technology used
in multiple games, and perhaps a few special products that
represent items that are not actually shipping products
(for example, "Website", or "Administration").

Many of Bugzilla's settings are configurable on a per-product
basis. The number of ``votes`` available to
users is set per-product, as is the number of votes
required to move a bug automatically from the UNCONFIRMED
status to the CONFIRMED status.

When creating or editing products the following options are
available:

Product
    The name of the product

Description
    A brief description of the product

Default milestone
    Select the default milestone for this product.

Closed for bug entry
    Select this box to prevent new bugs from being
    entered against this product.

Maximum votes per person
    Maximum votes a user is allowed to give for this
    product

Maximum votes a person can put on a single bug
    Maximum votes a user is allowed to give for this
    product in a single bug

Confirmation threshold
    Number of votes needed to automatically remove any
    bug against this product from the UNCONFIRMED state

Version
    Specify which version of the product bugs will be
    entered against.

Create chart datasets for this product
    Select to make chart datasets available for this product.

When editing a product there is also a link to edit Group Access Controls,
see :ref:`product-group-controls`.

.. _create-product:

Creating New Products
=====================

To create a new product:

#. Select ``Administration`` from the footer and then
   choose ``Products`` from the main administration page.

#. Select the ``Add`` link in the bottom right.

#. Enter the name of the product and a description. The
   Description field may contain HTML.

#. When the product is created, Bugzilla will give a message
   stating that a component must be created before any bugs can
   be entered against the new product. Follow the link to create
   a new component. See :ref:`components` for more
   information.

.. _edit-products:

Editing Products
================

To edit an existing product, click the "Products" link from the
"Administration" page. If the 'useclassification' parameter is
turned on, a table of existing classifications is displayed,
including an "Unclassified" category. The table indicates how many products
are in each classification. Click on the classification name to see its
products. If the 'useclassification' parameter is not in use, the table
lists all products directly. The product table summarizes the information
about the product defined
when the product was created. Click on the product name to edit these
properties, and to access links to other product attributes such as the
product's components, versions, milestones, and group access controls.

.. _comps-vers-miles-products:

Adding or Editing Components, Versions and Target Milestones
============================================================

To edit existing, or add new, Components, Versions or Target Milestones
to a Product, select the "Edit Components", "Edit Versions" or "Edit
Milestones" links from the "Edit Product" page. A table of existing
Components, Versions or Milestones is displayed. Click on a item name
to edit the properties of that item. Below the table is a link to add
a new Component, Version or Milestone.

For more information on components, see :ref:`components`.

For more information on versions, see :ref:`versions`.

For more information on milestones, see :ref:`milestones`.

.. _product-group-controls:

Assigning Group Controls to Products
====================================

On the ``Edit Product`` page, there is a link called
``Edit Group Access Controls``. The settings on this page
control the relationship of the groups to the product being edited.

Group Access Controls are an important aspect of using groups for
isolating products and restricting access to bugs filed against those
products. For more information on groups, including how to create, edit
add users to, and alter permission of, see :ref:`groups`.

After selecting the "Edit Group Access Controls" link from the "Edit
Product" page, a table containing all user-defined groups for this
Bugzilla installation is displayed. The system groups that are created
when Bugzilla is installed are not applicable to Group Access Controls.
Below is description of what each of these fields means.

Groups may be applicable (e.g bugs in this product can be associated
with this group) , default (e.g. bugs in this product are in this group
by default), and mandatory (e.g. bugs in this product must be associated
with this group) for each product. Groups can also control access
to bugs for a given product, or be used to make bugs for a product
totally read-only unless the group restrictions are met. The best way to
understand these relationships is by example. See
:ref:`group-control-examples` for examples of
product and group relationships.

.. note:: Products and Groups are not limited to a one-to-one relationship.
   Multiple groups can be associated with the same product, and groups
   can be associated with more than one product.

If any group has *Entry* selected, then the
product will restrict bug entry to only those users
who are members of *all* the groups with
*Entry* selected.

If any group has *Canedit* selected,
then the product will be read-only for any users
who are not members of *all* of the groups with
*Canedit* selected. *Only* users who
are members of all the *Canedit* groups
will be able to edit bugs for this product. This is an additional
restriction that enables finer-grained control over products rather
than just all-or-nothing access levels.

The following settings let you
choose privileges on a *per-product basis*.
This is a convenient way to give privileges to
some users for some products only, without having
to give them global privileges which would affect
all products.

Any group having *editcomponents*
selected  allows users who are in this group to edit all
aspects of this product, including components, milestones
and versions.

Any group having *canconfirm* selected
allows users who are in this group to confirm bugs
in this product.

Any group having *editbugs* selected allows
users who are in this group to edit all fields of
bugs in this product.

The *MemberControl* and
*OtherControl* are used in tandem to determine which
bugs will be placed in this group. The only allowable combinations of
these two parameters are listed in a table on the "Edit Group Access Controls"
page. Consult this table for details on how these fields can be used.
Examples of different uses are described below.

.. _group-control-examples:

Common Applications of Group Controls
=====================================

The use of groups is best explained by providing examples that illustrate
configurations for common use cases. The examples follow a common syntax:
*Group: Entry, MemberControl, OtherControl, CanEdit,
EditComponents, CanConfirm, EditBugs*. Where "Group" is the name
of the group being edited for this product. The other fields all
correspond to the table on the "Edit Group Access Controls" page. If any
of these options are not listed, it means they are not checked.

Basic Product/Group Restriction
-------------------------------

Suppose there is a product called "Bar". The
"Bar" product can only have bugs entered against it by users in the
group "Foo". Additionally, bugs filed against product "Bar" must stay
restricted to users to "Foo" at all times. Furthermore, only members
of group "Foo" can edit bugs filed against product "Bar", even if other
users could see the bug. This arrangement would achieved by the
following:

::

    Product Bar:
    foo: ENTRY, MANDATORY/MANDATORY, CANEDIT

Perhaps such strict restrictions are not needed for product "Bar". A
more lenient way to configure product "Bar" and group "Foo" would be:

::

    Product Bar:
    foo: ENTRY, SHOWN/SHOWN, EDITCOMPONENTS, CANCONFIRM, EDITBUGS

The above indicates that for product "Bar", members of group "Foo" can
enter bugs. Any one with permission to edit a bug against product "Bar"
can put the bug
in group "Foo", even if they themselves are not in "Foo". Anyone in group
"Foo" can edit all aspects of the components of product "Bar", can confirm
bugs against product "Bar", and can edit all fields of any bug against
product "Bar".

General User Access With Security Group
---------------------------------------

To permit any user to file bugs against "Product A",
and to permit any user to submit those bugs into a
group called "Security":

::

    Product A:
    security: SHOWN/SHOWN

General User Access With A Security Product
-------------------------------------------

To permit any user to file bugs against product called "Security"
while keeping those bugs from becoming visible to anyone
outside the group "SecurityWorkers" (unless a member of the
"SecurityWorkers" group removes that restriction):

::

    Product Security:
    securityworkers: DEFAULT/MANDATORY

Product Isolation With a Common Group
-------------------------------------

To permit users of "Product A" to access the bugs for
"Product A", users of "Product B" to access the bugs for
"Product B", and support staff, who are members of the "Support
Group" to access both, three groups are needed:

#. Support Group: Contains members of the support staff.

#. AccessA Group: Contains users of product A and the Support group.

#. AccessB Group: Contains users of product B and the Support group.

Once these three groups are defined, the product group controls
can be set to:

::

    Product A:
    AccessA: ENTRY, MANDATORY/MANDATORY
    Product B:
    AccessB: ENTRY, MANDATORY/MANDATORY

Perhaps the "Support Group" wants more control. For example,
the "Support Group"  could be permitted to make bugs inaccessible to
users of both groups "AccessA" and "AccessB".
Then, the "Support Group" could be permitted to publish
bugs relevant to all users in a third product (let's call it
"Product Common") that is read-only
to anyone outside the "Support Group". In this way the "Support Group"
could control bugs that should be seen by both groups.
That configuration would be:

::

    Product A:
    AccessA: ENTRY, MANDATORY/MANDATORY
    Support: SHOWN/NA
    Product B:
    AccessB: ENTRY, MANDATORY/MANDATORY
    Support: SHOWN/NA
    Product Common:
    Support: ENTRY, DEFAULT/MANDATORY, CANEDIT

Make a Product Read Only
------------------------

Sometimes a product is retired and should no longer have
new bugs filed against it (for example, an older version of a software
product that is no longer supported). A product can be made read-only
by creating a group called "readonly" and adding products to the
group as needed:

::

    Product A:
    ReadOnly: ENTRY, NA/NA, CANEDIT

.. note:: For more information on Groups outside of how they relate to products
   see :ref:`groups`.

.. _components:

Components
##########

Components are subsections of a Product. E.g. the computer game
you are designing may have a "UI"
component, an "API" component, a "Sound System" component, and a
"Plugins" component, each overseen by a different programmer. It
often makes sense to divide Components in Bugzilla according to the
natural divisions of responsibility within your Product or
company.

Each component has a default assignee and (if you turned it on in the parameters),
a QA Contact. The default assignee should be the primary person who fixes bugs in
that component. The QA Contact should be the person who will ensure
these bugs are completely fixed. The Assignee, QA Contact, and Reporter
will get email when new bugs are created in this Component and when
these bugs change. Default Assignee and Default QA Contact fields only
dictate the
*default assignments*;
these can be changed on bug submission, or at any later point in
a bug's life.

To create a new Component:

#. Select the ``Edit components`` link
   from the ``Edit product`` page

#. Select the ``Add`` link in the bottom right.

#. Fill out the ``Component`` field, a
   short ``Description``, the
   ``Default Assignee``, ``Default CC List``
   and ``Default QA Contact`` (if enabled).
   The ``Component Description`` field may contain a
   limited subset of HTML tags. The ``Default Assignee``
   field must be a login name already existing in the Bugzilla database.

.. _versions:

Versions
########

Versions are the revisions of the product, such as "Flinders
3.1", "Flinders 95", and "Flinders 2000". Version is not a multi-select
field; the usual practice is to select the earliest version known to have
the bug.

To create and edit Versions:

#. From the "Edit product" screen, select "Edit Versions"

#. You will notice that the product already has the default
   version "undefined". Click the "Add" link in the bottom right.

#. Enter the name of the Version. This field takes text only.
   Then click the "Add" button.

.. _milestones:

Milestones
##########

Milestones are "targets" that you plan to get a bug fixed by. For
example, you have a bug that you plan to fix for your 3.0 release, it
would be assigned the milestone of 3.0.

.. note:: Milestone options will only appear for a Product if you turned
   on the "usetargetmilestone" parameter in the "Bug Fields" tab of the
   "Parameters" page.

To create new Milestones, and set Default Milestones:

#. Select "Edit milestones" from the "Edit product" page.

#. Select "Add" in the bottom right corner.

#. Enter the name of the Milestone in the "Milestone" field. You
   can optionally set the "sortkey", which is a positive or negative
   number (-32768 to 32767) that defines where in the list this particular
   milestone appears. This is because milestones often do not
   occur in alphanumeric order For example, "Future" might be
   after "Release 1.2". Select "Add".

.. _flags-overview:

Flags
#####

Flags are a way to attach a specific status to a bug or attachment,
either ``+`` or ``-``. The meaning of these symbols depends on the text
the flag itself, but contextually they could mean pass/fail,
accept/reject, approved/denied, or even a simple yes/no. If your site
allows requestable flags, then users may set a flag to ``?`` as a
request to another user that they look at the bug/attachment, and set
the flag to its correct status.

.. _flags-simpleexample:

A Simple Example
================

A developer might want to ask their manager,
``Should we fix this bug before we release version 2.0?``
They might want to do this for a *lot* of bugs,
so it would be nice to streamline the process...

In Bugzilla, it would work this way:

#. The Bugzilla administrator creates a flag type called
   ``blocking2.0`` that shows up on all bugs in
   your product.
   It shows up on the ``Show Bug`` screen
   as the text ``blocking2.0`` with a drop-down box next
   to it. The drop-down box contains four values: an empty space,
   ``?``, ``-``, and ``+``.

#. The developer sets the flag to ``?``.

#. The manager sees the ``blocking2.0``
   flag with a ``?`` value.

#. If the manager thinks the feature should go into the product
   before version 2.0 can be released, he sets the flag to
   ``+``. Otherwise, he sets it to ``-``.

#. Now, every Bugzilla user who looks at the bug knows whether or
   not the bug needs to be fixed before release of version 2.0.

.. _flags-about:

About Flags
===========

.. _flag-values:

Values
------

Flags can have three values:

``?``
    A user is requesting that a status be set. (Think of it as 'A question is being asked'.)

``-``
    The status has been set negatively. (The question has been answered ``no``.)

``+``
    The status has been set positively.
    (The question has been answered ``yes``.)

Actually, there's a fourth value a flag can have --
``unset`` -- which shows up as a blank space. This
just means that nobody has expressed an opinion (or asked
someone else to express an opinion) about this bug or attachment.

.. _flag-askto:

Using flag requests
===================

If a flag has been defined as 'requestable', and a user has enough privileges
to request it (see below), the user can set the flag's status to ``?``.
This status indicates that someone (a.k.a. ``the requester``) is asking
someone else to set the flag to either ``+`` or ``-``.

If a flag has been defined as 'specifically requestable',
a text box will appear next to the flag into which the requester may
enter a Bugzilla username. That named person (a.k.a. ``the requestee``)
will receive an email notifying them of the request, and pointing them
to the bug/attachment in question.

If a flag has *not* been defined as 'specifically requestable',
then no such text-box will appear. A request to set this flag cannot be made of
any specific individual, but must be asked ``to the wind``.
A requester may ``ask the wind`` on any flag simply by leaving the text-box blank.

.. _flag-types:

Two Types of Flags
==================

Flags can go in two places: on an attachment, or on a bug.

.. _flag-type-attachment:

Attachment Flags
----------------

Attachment flags are used to ask a question about a specific
attachment on a bug.

Many Bugzilla installations use this to
request that one developer ``review`` another
developer's code before they check it in. They attach the code to
a bug report, and then set a flag on that attachment called
``review`` to
``review?boss@domain.com``.
boss@domain.com is then notified by email that
he has to check out that attachment and approve it or deny it.

For a Bugzilla user, attachment flags show up in three places:

#. On the list of attachments in the ``Show Bug``
   screen, you can see the current state of any flags that
   have been set to ?, +, or -. You can see who asked about
   the flag (the requester), and who is being asked (the
   requestee).

#. When you ``Edit`` an attachment, you can
   see any settable flag, along with any flags that have
   already been set. This ``Edit Attachment``
   screen is where you set flags to ?, -, +, or unset them.

#. Requests are listed in the ``Request Queue``, which
   is accessible from the ``My Requests`` link (if you are
   logged in) or ``Requests`` link (if you are logged out)
   visible in the footer of all pages.

.. _flag-type-bug:

Bug Flags
---------

Bug flags are used to set a status on the bug itself. You can
see Bug Flags in the ``Show Bug`` and ``Requests``
screens, as described above.

Only users with enough privileges (see below) may set flags on bugs.
This doesn't necessarily include the assignee, reporter, or users with the
``editbugs`` permission.

.. _flags-admin:

Administering Flags
===================

If you have the ``editcomponents`` permission, you can
edit Flag Types from the main administration page. Clicking the
``Flags`` link will bring you to the ``Administer
Flag Types`` page. Here, you can select whether you want
to create (or edit) a Bug flag, or an Attachment flag.

No matter which you choose, the interface is the same, so we'll
just go over it once.

.. _flags-edit:

Editing a Flag
--------------

To edit a flag's properties, just click the flag's name.
That will take you to the same
form as described below (:ref:`flags-create`).

.. _flags-create:

Creating a Flag
---------------

When you click on the ``Create a Flag Type for...``
link, you will be presented with a form. Here is what the fields in
the form mean:

.. _flags-create-field-name:

Name
~~~~

This is the name of the flag. This will be displayed
to Bugzilla users who are looking at or setting the flag.
The name may contain any valid Unicode characters except commas
and spaces.

.. _flags-create-field-description:

Description
~~~~~~~~~~~

The description describes the flag in more detail. It is visible
in a tooltip when hovering over a flag either in the ``Show Bug``
or ``Edit Attachment`` pages. This field can be as
long as you like, and can contain any character you want.

.. _flags-create-field-category:

Category
~~~~~~~~

Default behaviour for a newly-created flag is to appear on
products and all components, which is why ``__Any__:__Any__``
is already entered in the ``Inclusions`` box.
If this is not your desired behaviour, you must either set some
exclusions (for products on which you don't want the flag to appear),
or you must remove ``__Any__:__Any__`` from the Inclusions box
and define products/components specifically for this flag.

To create an Inclusion, select a Product from the top drop-down box.
You may also select a specific component from the bottom drop-down box.
(Setting ``__Any__`` for Product translates to,
``all the products in this Bugzilla``.
Selecting  ``__Any__`` in the Component field means
``all components in the selected product.``)
Selections made, press ``Include``, and your
Product/Component pairing will show up in the ``Inclusions`` box on the right.

To create an Exclusion, the process is the same; select a Product from the
top drop-down box, select a specific component if you want one, and press
``Exclude``. The Product/Component pairing will show up in the
``Exclusions`` box on the right.

This flag *will* and *can* be set for any
products/components that appearing in the ``Inclusions`` box
(or which fall under the appropriate ``__Any__``).
This flag *will not* appear (and therefore cannot be set) on
any products appearing in the ``Exclusions`` box.
*IMPORTANT: Exclusions override inclusions.*

You may select a Product without selecting a specific Component,
but you can't select a Component without a Product, or to select a
Component that does not belong to the named Product. If you do so,
Bugzilla will display an error message, even if all your products
have a component by that name.

*Example:* Let's say you have a product called
``Jet Plane`` that has thousands of components. You want
to be able to ask if a problem should be fixed in the next model of
plane you release. We'll call the flag ``fixInNext``.
But, there's one component in ``Jet Plane,``
called ``Pilot.`` It doesn't make sense to release a
new pilot, so you don't want to have the flag show up in that component.
So, you include ``Jet Plane:__Any__`` and you exclude
``Jet Plane:Pilot``.

.. _flags-create-field-sortkey:

Sort Key
~~~~~~~~

Flags normally show up in alphabetical order. If you want them to
show up in a different order, you can use this key set the order on each flag.
Flags with a lower sort key will appear before flags with a higher
sort key. Flags that have the same sort key will be sorted alphabetically,
but they will still be after flags with a lower sort key, and before flags
with a higher sort key.

*Example:* I have AFlag (Sort Key 100), BFlag (Sort Key 10),
CFlag (Sort Key 10), and DFlag (Sort Key 1). These show up in
the order: DFlag, BFlag, CFlag, AFlag.

.. _flags-create-field-active:

Active
~~~~~~

Sometimes, you might want to keep old flag information in the
Bugzilla database, but stop users from setting any new flags of this type.
To do this, uncheck ``active``. Deactivated
flags will still show up in the UI if they are ?, +, or -, but they
may only be cleared (unset), and cannot be changed to a new value.
Once a deactivated flag is cleared, it will completely disappear from a
bug/attachment, and cannot be set again.

.. _flags-create-field-requestable:

Requestable
~~~~~~~~~~~

New flags are, by default, ``requestable``, meaning that they
offer users the ``?`` option, as well as ``+``
and ``-``.
To remove the ? option, uncheck ``requestable``.

.. _flags-create-field-specific:

Specifically Requestable
~~~~~~~~~~~~~~~~~~~~~~~~

By default this box is checked for new flags, meaning that users may make
flag requests of specific individuals. Unchecking this box will remove the
text box next to a flag; if it is still requestable, then requests may
only be made ``to the wind.`` Removing this after specific
requests have been made will not remove those requests; that data will
stay in the database (though it will no longer appear to the user).

.. _flags-create-field-multiplicable:

Multiplicable
~~~~~~~~~~~~~

Any flag with ``Multiplicable`` set (default for new flags is 'on')
may be set more than once. After being set once, an unset flag
of the same type will appear below it with ``addl.`` (short for
``additional``) before the name. There is no limit to the number of
times a Multiplicable flags may be set on the same bug/attachment.

.. _flags-create-field-cclist:

CC List
~~~~~~~

If you want certain users to be notified every time this flag is
set to ?, -, +, or unset, add them here. This is a comma-separated
list of email addresses that need not be restricted to Bugzilla usernames.

.. _flags-create-grant-group:

Grant Group
~~~~~~~~~~~

When this field is set to some given group, only users in the group
can set the flag to ``+`` and ``-``. This
field does not affect who can request or cancel the flag. For that,
see the ``Request Group`` field below. If this field
is left blank, all users can set or delete this flag. This field is
useful for restricting which users can approve or reject requests.

.. _flags-create-request-group:

Request Group
~~~~~~~~~~~~~

When this field is set to some given group, only users in the group
can request or cancel this flag. Note that this field has no effect
if the ``grant group`` field is empty. You can set the
value of this field to a different group, but both fields have to be
set to a group for this field to have an effect.

.. COMMENT: flags-create

.. _flags-delete:

Deleting a Flag
---------------

When you are at the ``Administer Flag Types`` screen,
you will be presented with a list of Bug flags and a list of Attachment
Flags.

To delete a flag, click on the ``Delete`` link next to
the flag description.

.. warning:: Once you delete a flag, it is *gone* from
   your Bugzilla. All the data for that flag will be deleted.
   Everywhere that flag was set, it will disappear,
   and you cannot get that data back. If you want to keep flag data,
   but don't want anybody to set any new flags or change current flags,
   unset ``active`` in the flag Edit form.

.. COMMENT: flags-admin

.. COMMENT: XXX We should add a "Uses of Flags" section, here, with examples.

.. COMMENT: flags

.. _keywords:

Keywords
########

The administrator can define keywords which can be used to tag and
categorise bugs. For example, the keyword "regression" is commonly used.
A company might have a policy stating all regressions
must be fixed by the next release - this keyword can make tracking those
bugs much easier.

Keywords are global, rather than per-product. If the administrator changes
a keyword currently applied to any bugs, the keyword cache must be rebuilt
using the :ref:`sanitycheck` script. Currently keywords cannot
be marked obsolete to prevent future usage.

Keywords can be created, edited or deleted by clicking the "Keywords"
link in the admin page. There are two fields for each keyword - the keyword
itself and a brief description. Once created, keywords can be selected
and applied to individual bugs in that bug's "Details" section.

.. _custom-fields:

Custom Fields
#############

The release of Bugzilla 3.0 added the ability to create Custom Fields.
Custom Fields are treated like any other field - they can be set in bugs
and used for search queries. Administrators should keep in mind that
adding too many fields can make the user interface more complicated and
harder to use. Custom Fields should be added only when necessary and with
careful consideration.

.. note:: Before adding a Custom Field, make sure that Bugzilla cannot already
   do the desired behavior. Many Bugzilla options are not enabled by
   default, and many times Administrators find that simply enabling
   certain options that already exist is sufficient.

Administrators can manage Custom Fields using the
``Custom Fields`` link on the Administration page. The Custom
Fields administration page displays a list of Custom Fields, if any exist,
and a link to "Add a new custom field".

.. _add-custom-fields:

Adding Custom Fields
====================

To add a new Custom Field, click the "Add a new custom field" link. This
page displays several options for the new field, described below.

The following attributes must be set for each new custom field:

- *Name:*
  The name of the field in the database, used internally. This name
  MUST begin with ``cf_`` to prevent confusion with
  standard fields. If this string is omitted, it will
  be automatically added to the name entered.

- *Description:*
  A brief string which is used as the label for this Custom Field.
  That is the string that users will see, and should be
  short and explicit.

- *Type:*
  The type of field to create. There are
  several types available:

  Bug ID:
      A field where you can enter the ID of another bug from
      the same Bugzilla installation. To point to a bug in a remote
      installation, use the See Also field instead.
  Large Text Box:
      A multiple line box for entering free text.
  Free Text:
      A single line box for entering free text.
  Multiple-Selection Box:
      A list box where multiple options
      can be selected. After creating this field, it must be edited
      to add the selection options. See
      :ref:`edit-values-list` for information about
      editing legal values.
  Drop Down:
      A list box where only one option can be selected.
      After creating this field, it must be edited to add the
      selection options. See
      :ref:`edit-values-list` for information about
      editing legal values.
  Date/Time:
      A date field. This field appears with a
      calendar widget for choosing the date.

- *Sortkey:*
  Integer that determines in which order Custom Fields are
  displayed in the User Interface, especially when viewing a bug.
  Fields with lower values are displayed first.

- *Reverse Relationship Description:*
  When the custom field is of type ``Bug ID``, you can
  enter text here which will be used as label in the referenced
  bug to list bugs which point to it. This gives you the ability
  to have a mutual relationship between two bugs.

- *Can be set on bug creation:*
  Boolean that determines whether this field can be set on
  bug creation. If not selected, then a bug must be created
  before this field can be set. See :ref:`bugreports`
  for information about filing bugs.

- *Displayed in bugmail for new bugs:*
  Boolean that determines whether the value set on this field
  should appear in bugmail when the bug is filed. This attribute
  has no effect if the field cannot be set on bug creation.

- *Is obsolete:*
  Boolean that determines whether this field should
  be displayed at all. Obsolete Custom Fields are hidden.

- *Is mandatory:*
  Boolean that determines whether this field must be set.
  For single and multi-select fields, this means that a (non-default)
  value must be selected, and for text and date fields, some text
  must be entered.

- *Field only appears when:*
  A custom field can be made visible when some criteria is met.
  For instance, when the bug belongs to one or more products,
  or when the bug is of some given severity. If left empty, then
  the custom field will always be visible, in all bugs.

- *Field that controls the values that appear in this field:*
  When the custom field is of type ``Drop Down`` or
  ``Multiple-Selection Box``, you can restrict the
  availability of the values of the custom field based on the
  value of another field. This criteria is independent of the
  criteria used in the ``Field only appears when``
  setting. For instance, you may decide that some given value
  ``valueY`` is only available when the bug status
  is RESOLVED while the value ``valueX`` should
  always be listed.
  Once you have selected the field which should control the
  availability of the values of this custom field, you can
  edit values of this custom field to set the criteria, see
  :ref:`edit-values-list`.

.. _edit-custom-fields:

Editing Custom Fields
=====================

As soon as a Custom Field is created, its name and type cannot be
changed. If this field is a drop down menu, its legal values can
be set as described in :ref:`edit-values-list`. All
other attributes can be edited as described above.

.. _delete-custom-fields:

Deleting Custom Fields
======================

Only custom fields which are marked as obsolete, and which never
have been used, can be deleted completely (else the integrity
of the bug history would be compromised). For custom fields marked
as obsolete, a "Delete" link will appear in the ``Action``
column. If the custom field has been used in the past, the deletion
will be rejected. But marking the field as obsolete is sufficient
to hide it from the user interface entirely.

.. _edit-values:

Legal Values
############

Legal values for the operating system, platform, bug priority and
severity, custom fields of type ``Drop Down`` and
``Multiple-Selection Box`` (see :ref:`custom-fields`),
as well as the list of valid bug statuses and resolutions can be
customized from the same interface. You can add, edit, disable and
remove values which can be used with these fields.

.. _edit-values-list:

Viewing/Editing legal values
============================

Editing legal values requires ``admin`` privileges.
Select "Field Values" from the Administration page. A list of all
fields, both system fields and Custom Fields, for which legal values
can be edited appears. Click a field name to edit its legal values.

There is no limit to how many values a field can have, but each value
must be unique to that field. The sortkey is important to display these
values in the desired order.

When the availability of the values of a custom field is controlled
by another field, you can select from here which value of the other field
must be set for the value of the custom field to appear.

.. _edit-values-delete:

Deleting legal values
=====================

Legal values from Custom Fields can be deleted, but only if the
following two conditions are respected:

#. The value is not used by default for the field.

#. No bug is currently using this value.

If any of these conditions is not respected, the value cannot be deleted.
The only way to delete these values is to reassign bugs to another value
and to set another value as default for the field.

.. _bug_status_workflow:

Bug Status Workflow
###################

The bug status workflow is no longer hardcoded but can be freely customized
from the web interface. Only one bug status cannot be renamed nor deleted,
UNCONFIRMED, but the workflow involving it is free. The configuration
page displays all existing bug statuses twice, first on the left for bug
statuses we come from and on the top for bug statuses we move to.
If the checkbox is checked, then the transition between the two bug statuses
is legal, else it's forbidden independently of your privileges. The bug status
used for the "duplicate_or_move_bug_status" parameter must be part of the
workflow as that is the bug status which will be used when duplicating or
moving a bug, so it must be available from each bug status.

When the workflow is set, the "View Current Triggers" link below the table
lets you set which transitions require a comment from the user.

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

.. _groups:

Groups and Group Security
#########################

Groups allow for separating bugs into logical divisions.
Groups are typically used
to isolate bugs that should only be seen by certain people. For
example, a company might create a different group for each one of its customers
or partners. Group permissions could be set so that each partner or customer would
only have access to their own bugs. Or, groups might be used to create
variable access controls for different departments within an organization.
Another common use of groups is to associate groups with products,
creating isolation and access control on a per-product basis.

Groups and group behaviors are controlled in several places:

#. The group configuration page. To view or edit existing groups, or to
   create new groups, access the "Groups" link from the "Administration"
   page. This section of the manual deals primarily with the aspect of
   group controls accessed on this page.

#. Global configuration parameters. Bugzilla has several parameters
   that control the overall default group behavior and restriction
   levels. For more information on the parameters that control
   group behavior globally, see :ref:`param-group-security`.

#. Product association with groups. Most of the functionality of groups
   and group security is controlled at the product level. Some aspects
   of group access controls for products are discussed in this section,
   but for more detail see :ref:`product-group-controls`.

#. Group access for users. See :ref:`users-and-groups` for
   details on how users are assigned group access.

Group permissions are such that if a bug belongs to a group, only members
of that group can see the bug. If a bug is in more than one group, only
members of *all* the groups that the bug is in can see
the bug. For information on granting read-only access to certain people and
full edit access to others, see :ref:`product-group-controls`.

.. note:: By default, bugs can also be seen by the Assignee, the Reporter, and
   by everyone on the CC List, regardless of whether or not the bug would
   typically be viewable by them. Visibility to the Reporter and CC List can
   be overridden (on a per-bug basis) by bringing up the bug, finding the
   section that starts with ``Users in the roles selected below...``
   and un-checking the box next to either 'Reporter' or 'CC List' (or both).

.. _create-groups:

Creating Groups
===============

To create a new group, follow the steps below:

#. Select the ``Administration`` link in the page footer,
   and then select the ``Groups`` link from the
   Administration page.

#. A table of all the existing groups is displayed. Below the table is a
   description of all the fields. To create a new group, select the
   ``Add Group`` link under the table of existing groups.

#. There are five fields to fill out. These fields are documented below
   the form. Choose a name and description for the group. Decide whether
   this group should be used for bugs (in all likelihood this should be
   selected). Optionally, choose a regular expression that will
   automatically add any matching users to the group, and choose an
   icon that will help identify user comments for the group. The regular
   expression can be useful, for example, to automatically put all users
   from the same company into one group (if the group is for a specific
   customer or partner).

   .. note:: If ``User RegExp`` is filled out, users whose email
      addresses match the regular expression will automatically be
      members of the group as long as their email addresses continue
      to match the regular expression. If their email address changes
      and no longer matches the regular expression, they will be removed
      from the group. Versions 2.16 and older of Bugzilla did not automatically
      remove users who's email addresses no longer matched the RegExp.

   .. warning:: If specifying a domain in the regular expression, end
      the regexp with a "$". Otherwise, when granting access to
      "@mycompany\\.com", access will also be granted to
      'badperson@mycompany.com.cracker.net'. Use the syntax,
      '@mycompany\\.com$' for the regular expression.

#. After the new group is created, it can be edited for additional options.
   The "Edit Group" page allows for specifying other groups that should be included
   in this group and which groups should be permitted to add and delete
   users from this group. For more details, see :ref:`edit-groups`.

.. _edit-groups:

Editing Groups and Assigning Group Permissions
==============================================

To access the "Edit Groups" page, select the
``Administration`` link in the page footer,
and then select the ``Groups`` link from the Administration page.
A table of all the existing groups is displayed. Click on a group name
you wish to edit or control permissions for.

The "Edit Groups" page contains the same five fields present when
creating a new group. Below that are two additional sections, "Group
Permissions," and "Mass Remove". The "Mass Remove" option simply removes
all users from the group who match the regular expression entered. The
"Group Permissions" section requires further explanation.

The "Group Permissions" section on the "Edit Groups" page contains four sets
of permissions that control the relationship of this group to other
groups. If the 'usevisibilitygroups' parameter is in use (see
:ref:`parameters`) two additional sets of permissions are displayed.
Each set consists of two select boxes. On the left, a select box
with a list of all existing groups. On the right, a select box listing
all groups currently selected for this permission setting (this box will
be empty for new groups). The way these controls allow groups to relate
to one another is called *inheritance*.
Each of the six permissions is described below.

*Groups That Are a Member of This Group*
    Members of any groups selected here will automatically have
    membership in this group. In other words, members of any selected
    group will inherit membership in this group.

*Groups That This Group Is a Member Of*
    Members of this group will inherit membership to any group
    selected here. For example, suppose the group being edited is
    an Admin group. If there are two products  (Product1 and Product2)
    and each product has its
    own group (Group1 and Group2), and the Admin group
    should have access to both products,
    simply select both Group1 and Group2 here.

*Groups That Can Grant Membership in This Group*
    The members of any group selected here will be able add users
    to this group, even if they themselves are not in this group.

*Groups That This Group Can Grant Membership In*
    Members of this group can add users to any group selected here,
    even if they themselves are not in the selected groups.

*Groups That Can See This Group*
    Members of any selected group can see the users in this group.
    This setting is only visible if the 'usevisibilitygroups' parameter
    is enabled on the Bugzilla Configuration page. See
    :ref:`parameters` for information on configuring Bugzilla.

*Groups That This Group Can See*
    Members of this group can see members in any of the selected groups.
    This setting is only visible if the 'usevisibilitygroups' parameter
    is enabled on the the Bugzilla Configuration page. See
    :ref:`parameters` for information on configuring Bugzilla.

.. _users-and-groups:

Assigning Users to Groups
=========================

A User can become a member of a group in several ways:

#. The user can be explicitly placed in the group by editing
   the user's profile. This can be done by accessing the "Users" page
   from the "Administration" page. Use the search form to find the user
   you want to edit group membership for, and click on their email
   address in the search results to edit their profile. The profile
   page lists all the groups, and indicates if the user is a member of
   the group either directly or indirectly. More information on indirect
   group membership is below. For more details on User administration,
   see :ref:`useradmin`.

#. The group can include another group of which the user is
   a member. This is indicated by square brackets around the checkbox
   next to the group name in the user's profile.
   See :ref:`edit-groups` for details on group inheritance.

#. The user's email address can match the regular expression
   that has been specified to automatically grant membership to
   the group. This is indicated by "\*" around the check box by the
   group name in the user's profile.
   See :ref:`create-groups` for details on
   the regular expression option when creating groups.

Assigning Group Controls to Products
====================================

The primary functionality of groups is derived from the relationship of
groups to products. The concepts around segregating access to bugs with
product group controls can be confusing. For details and examples on this
topic, see :ref:`product-group-controls`.

.. _sanitycheck:

Checking and Maintaining Database Integrity
###########################################

Over time it is possible for the Bugzilla database to become corrupt
or to have anomalies.
This could happen through normal usage of Bugzilla, manual database
administration outside of the Bugzilla user interface, or from some
other unexpected event. Bugzilla includes a "Sanity Check" script that
can perform several basic database checks, and repair certain problems or
inconsistencies.

To run the "Sanity Check" script, log in as an Administrator and click the
"Sanity Check" link in the admin page. Any problems that are found will be
displayed in red letters. If the script is capable of fixing a problem,
it will present a link to initiate the fix. If the script cannot
fix the problem it will require manual database administration or recovery.

The "Sanity Check" script can also be run from the command line via the perl
script :file:`sanitycheck.pl`. The script can also be run as
a :command:`cron` job. Results will be delivered by email.

The "Sanity Check" script should be run on a regular basis as a matter of
best practice.

.. warning:: The "Sanity Check" script is no substitute for a competent database
   administrator. It is only designed to check and repair basic database
   problems.


