:orphan:

.. _email:

Email
#####

Bugzilla requires the ability to set up email. You have a number of choices
here. The simplest is to get Gmail or some other email provider to do the
work for you, but you can also hand the mail off to a local email server,
or run one yourself on the Bugzilla machine.

Bugzilla's approach to email is configured in the :guilabel:`Email` section
of the Parameters.

.. todo:: Bug: description of mail_delivery_method talks about Qmail, and is in
          other ways wrong.

.. _install-MTA:

Use Another Mail Server
=======================

This section corresponds to choosing a :param:`mail_delivery_method` of
:paramval:`SMTP`.

This method passes the email off to an existing mail server. Your
organization may well already have one running for their internal email, and
may prefer to use it for confidentiality reasons. If so, you need the
following information about it:

* The domain name of the server (Parameter: :param:`smtpserver`)
* The username and password to use (Parameters: :param:`smtp_username` and 
  :param:`smtp_password`)
* Whether the server uses SSL (Parameter: :param:`smtp_ssl`)
* The address you should be sending mail 'From' (Parameter:
  :param:`mailfrom``)

If your organization does not run its own mail server, you can use the
services of one of any number of popular email providers.

Gmail
-----

Visit https://gmail.com and create a new Gmail account for your Bugzilla to
use. Then, set the following parameter values in the "Email" section:

* :param:`mail_delivery_method`: :paramval:`SMTP`
* :param:`mailfrom`: :paramval:`new_gmail_address@gmail.com`
* :param:`smtpserver`: :paramval:`smtp.gmail.com:465`
* :param:`smtp_username`: :paramval:`new_gmail_address@gmail.com`
* :param:`smtp_password`: :paramval:`new_gmail_password`
* :param:`smtp_ssl`: :paramval:`On`

Run Your Own Mail Server
========================

This section corresponds to choosing a :param:`mail_delivery_method` of
:paramval:`Sendmail`.

.. todo:: Do we still need this? Why would anyone want to do this in 2014?

Unless you know what you are doing, and can deal with the possible problems
of spam, bounces and blacklists, it is probably unwise to set up your own
mail server just for Bugzilla. However, if you wish to do so, here is some
guidance.

On Linux, any Sendmail-compatible MTA (Mail Transfer Agent) will
suffice.  Sendmail, Postfix, qmail and Exim are examples of common
MTAs. Sendmail is the original Unix MTA, but the others are easier to
configure, and therefore many people replace Sendmail with Postfix or
Exim. They are drop-in replacements, so Bugzilla will not
distinguish between them.

If you are using Sendmail, version 8.7 or higher is required. If you are
using a Sendmail-compatible MTA, it must be compatible with at least version
8.7 of Sendmail.

Detailed information on configuring an MTA is outside the scope of this
document. Consult the manual for the specific MTA you choose for detailed
installation instructions. Each of these programs will have their own
configuration files where you must configure certain parameters to
ensure that the mail is delivered properly. They are implemented
as services, and you should ensure that the MTA is in the auto-start
list of services for the machine.

If a simple mail sent with the command-line :file:`mail` program
succeeds, then Bugzilla should also be fine.
