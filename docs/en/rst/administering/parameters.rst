.. _parameters:

Parameters
##########

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
    :file:`data/params` and set user_verify_class to
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
    :file:`data/params` and set user_verify_class to
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
