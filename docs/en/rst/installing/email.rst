.. _email:

Email
#####

Bugzilla requires the ability to set up email. You have a number of choices
here. The simplest is to get Gmail or some other email provider to do the
work for you, but you can also hand the mail off to a local email server,
or run one yourself on the Bugzilla machine.

.. _install-MTA:

Mail Transfer Agent (MTA)
=========================

Bugzilla is dependent on the availability of an e-mail system for its
user authentication and for other tasks.

.. note:: This is not entirely true.  It is possible to completely disable
   email sending, or to have Bugzilla store email messages in a
   file instead of sending them.  However, this is mainly intended
   for testing, as disabling or diverting email on a production
   machine would mean that users could miss important events (such
   as bug changes or the creation of new accounts).
   For more information, see the ``mail_delivery_method`` parameter
   in :ref:`parameters`.

On Linux, any Sendmail-compatible MTA (Mail Transfer Agent) will
suffice.  Sendmail, Postfix, qmail and Exim are examples of common
MTAs. Sendmail is the original Unix MTA, but the others are easier to
configure, and therefore many people replace Sendmail with Postfix or
Exim. They are drop-in replacements, so Bugzilla will not
distinguish between them.

If you are using Sendmail, version 8.7 or higher is required.
If you are using a Sendmail-compatible MTA, it must be congruent with
at least version 8.7 of Sendmail.

Consult the manual for the specific MTA you choose for detailed
installation instructions. Each of these programs will have their own
configuration files where you must configure certain parameters to
ensure that the mail is delivered properly. They are implemented
as services, and you should ensure that the MTA is in the auto-start
list of services for the machine.

If a simple mail sent with the command-line 'mail' program
succeeds, then Bugzilla should also be fine.
