.. _quick-start:

Quick Start (Ubuntu Linux 22.04)
################################

This quick start guide makes installing Bugzilla as simple as possible for
those who are able to choose their environment. It creates a system using
Ubuntu Linux 22.04 LTS, Apache and MariaDB. It requires a little familiarity
with Linux and the command line.

.. note:: Harmony's dependencies have major changes from previous
  versions of Bugzilla. The libraries are now installed as local 
  Perl modules via ``carton`` instead as system-wide Debian packages.

Running On Your Own Hardware
============================

Ubuntu 22.04 LTS Server requires a 64-bit processor.
Bugzilla itself has no prerequisites beyond that, although you should pick
reliable hardware. 

.. todo:: 
  What is reliable hardware?

Install the OS
--------------

Get `Ubuntu Server 22.04 LTS <https://www.ubuntu.com/download/server>`_
and follow the `installation instructions 
<https://www.ubuntu.com/download/server/install-ubuntu-server>`_.
Here are some tips:

* You do not need an encrypted lvm group, root or home directory.
* Choose all the defaults for the "partitioning" part (excepting of course
  where the default is "No" and you need to press "Yes" to continue).
* Choose any server name you like.
* When creating the initial Linux user, call it ``bugzilla``, give it a
  strong password, and write that password down.
* From the install options, choose "OpenSSH Server".

Reboot when the installer finishes.

Become root
-----------

ssh to the machine as the 'bugzilla' user, or start a console. Then:

:command:`sudo su`

Running on a VPS (Virtual Private Server)
=========================================

.. todo::
  Also need sizing for this

Creating a VPS
--------------

Create a new VPS instance using Ubuntu 22.04 (LTS) for AMD64 architectures.

Choose an instance of at least 1GB memory and sufficient disc for the MariaDB
instance, an SSD is preferred.

Root Access 
-----------

Depending on your provider, you may be creating a user in the ``sudoers`` group,
or providing a public key to a SSH certificate you create on your computer which
will you allow you to connect to the VPS as root, which you will need in the
following steps.

.. warning:: Do not set a password for root on your VPS server. Either use an SSH
   key to connect as root, or log in as an unprivileged user in the ``sudoers`` 
   group.

Become root
-----------

Switch to the root user, either by logging in as an unprivileged user, and running
the command:

:command:`sudo su`

or logging in as root using a SSH key.

Install Prerequisites
=====================

As root, run the following:

:command:`apt install git nano build-essential mariadb-server libmariadb-dev perlmagick graphviz python3-sphinx rst2pdf carton`

Configure MySQL
===============

The following instructions use the simple :file:`nano` editor you installed 
in the previous step, but use any text editor you are comfortable with.

:command:`nano /etc/mysql/mariadb.conf.d/50-server.cnf`

Set the following values, which increase the maximum attachment size and
make it possible to search for short words and terms:

* Uncomment and alter on Line 34 to have a value of at least: ``max_allowed_packet=100M``
* Add as new line 42, in the ``[mysqld]`` section: ``ft_min_word_len=2``

Save and exit.

Create a database ``bugs`` for Bugzilla:

:command:`mysql -u root -e "CREATE DATABASE IF NOT EXISTS bugs CHARACTER SET = 'utf8'"`

Then, add a user to MySQL for Bugzilla to use:

:command:`mysql -u root -e "GRANT ALL PRIVILEGES ON bugs.* TO bugs@localhost IDENTIFIED BY '$db_pass'"`

Replace ``$db_pass`` with a strong password you have generated. Write it down.
You should make ``$db_pass`` different to your password.

Restart MySQL:

:command:`service mysql restart`

Download Bugzilla
=================

Get it from our Git repository:

:command:`mkdir -p /var/www/webapps`

:command:`cd /var/www/webapps`

:command:`git clone https://github.com/bugzilla/harmony.git bugzilla`

Install Bugzilla
================

In the same directory you cloned Bugzilla to, run:

:command:`perl Makefile.PL`

:command:`make cpanfile GEN_CPANFILE_ARGS="-D better_xff -D jsonrpc -D xmlrpc -D mysql"`

:command:`carton install`

The ``carton`` command will take some time to run. 

Check Setup
===========

Bugzilla comes with a :file:`checksetup.pl` script which helps with the
installation process. It will need to be run twice. The first time, it
generates a config file (called :file:`localconfig`) for the database
access information.

:command:`./checksetup.pl`

Edit :file:`localconfig`
========================

Now you can edit the ``localconfig`` created in the previous step.

:command:`nano localconfig`

You will need to set the following values:

.. todo:: 
  is ``$webservergroup`` still needed?

* :param:`$db_pass`:
  :paramval:`the password for the bugs user you created in MariaDB a few steps ago`
* :param:`$urlbase`:
  :paramval:`http://localhost:3001/` or :paramval:`http://<ip address>:3001/`
* :param:`$canonical_urlbase`:
  :paramval:`the value you set in $urlbase`

Check Setup (again)
===================

Run the :file:`checksetup.pl` script again to set up the database.

:command:`./checksetup.pl`

.. todo::
  ./checksetup.pl does not ask for an admin account address and password.
  There's an option to promote an existing account to an administrator, 
  but it doesn't create an account. And you need an admin user to to able
  to log in to set up email for account creation.

Start Server
============

The server is started using the ``bugzilla.pl`` script.

:command:`./bugzilla.pl daemon`

Will start start Bugzilla as a web app on port 3001.

Test Server
===========

.. todo::
  Is this still relevant? I see errors for:
  TEST-WARNING Failed to find the GID for the 'httpd' process, unable to validate webservergroup.
  Use of uninitialized value $response in pattern match (m//) at ./testserver.pl line 105.
  Use of uninitialized value $response in pattern match (m//) at ./testserver.pl line 108.

:command:`./testserver.pl http://localhost:3001/bugzilla`

All the tests should pass. You will get a warning about failing to run
``gdlib-config``; just ignore it.

.. todo:: ``gdlib-config`` is no longer in Ubuntu.

Access Via Web Browser
======================

Access the front page:

:command:`lynx http://localhost:3001/`

It's not really possible to use Bugzilla for real through Lynx, but you
can view the front page to validate visually that it's up and running.

You might well need to configure your DNS such that the server has, and
is reachable by, a name rather than IP address. Doing so is out of scope
of this document. In the mean time, it is available on your local network
at ``http://<ip address>/``, where ``<ip address>`` is (unless you
have a complex network setup) the address starting with 192 or 10 displayed 
when you run :command:`hostname -I`.

Accessing Bugzilla from the Internet
====================================

To be able to access Bugzilla from anywhere in the world, you don't have
to make it internet facing at all, there are free VPN services that let
you set up your own network that is accessible anywhere. One of those is
Tailscale, which has a fairly accessible `Quick Start guide <https://tailscale.com/kb/1017/install/>`_.

If you are setting up an internet facing Bugzilla, it's essential to set
up SSL, so that the communication between the server and users is
encrypted. For local and intranet installation this matters less, and
for those cases, you could set up a self signed local certificate
instead.

There are a few ways to set up free SSL thanks to `Let's Encrypt <https://letsencrypt.org/>`_.
The two major ones would be Apache's `mod_md <https://httpd.apache.org/docs/2.4/mod/mod_md.html>`_
and EFF's `certbot <https://certbot.eff.org/instructions?ws=apache&os=ubuntufocal>`_,
but we don't cover the exact specifics of this here, as that's out of
scope of this guide.

Configure Bugzilla
==================

Once you have worked out how to access your Bugzilla in a graphical
web browser, bring up the front page, click :guilabel:`Log In` in the
header, and log in as the admin user you defined in step 10.

Click the :guilabel:`Parameters` link on the page it gives you, and set
the following parameters in the :guilabel:`Required Settings` section:

* :param:`urlbase`:
  :paramval:`http://<servername>/` or :paramval:`http://<ip address>/`
* :param:`ssl_redirect`:
  :paramval:`on` if you set up an SSL certificate

Click :guilabel:`Save Changes` at the bottom of the page.

In order to send bugmail and enable signups for users, you must have:

* A domain that your Bugzilla instance will send mail from. 
* An SMTP host

The first is usually the domain or subdomain of your Bugzilla hostname. 
You will need to set up MX records for the host or service
at the domain name service provider for that domain, please check with
your email provider's documentation.

The second is a SMTP server you or your organization uses, or a mail
delivery service such as SendGrid or MailGun.

To configure your Bugzilla installation to send mail, open the Email section 
of the Parameters using the link in the left column, and set the following values:

* :param:`mail_delivery_method`: :paramval:`SMTP`
* :param:`mailfrom`: :paramval:`user@domain`
* :param:`smtpserver`: :paramval:`smtp.hostname:465`
* :param:`smtp_username`: :paramval:`username`
* :param:`smtp_password`: :paramval:`password`
* :param:`smtp_ssl`: :paramval:`On`

Click :guilabel:`Save Changes` at the bottom of the page.

