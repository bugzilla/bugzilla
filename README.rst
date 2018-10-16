=========================
BMO: bugzilla.mozilla.org
=========================

BMO is Mozilla's highly customized version of Bugzilla.

.. image:: https://circleci.com/gh/mozilla-bteam/bmo/tree/master.svg?style=svg
    :target: https://circleci.com/gh/mozilla-bteam/bmo/tree/master

.. contents::
..
    1  Using Vagrant (For Development)
      1.1  Setup Vagrant VMs
      1.2  Making Changes and Seeing them
      1.3  Technical Details
      1.4  Perl Shell (re.pl, repl)
    2  Using Docker Compose (For Development)
    3  Docker Container
      3.1  Container Arguments
      3.2  Environmental Variables
      3.3  Persistent Data Volume
    4. Development Tips
      4.1  Testing Emails

If you want to contribute to BMO, you can fork this repo and get a local copy
of BMO running in a few minutes using Vagrant or Docker.

Using Vagrant (For Development)
===============================

You will need to install the following software:

* Vagrant 1.9.1 or later

Doing this on OSX can be accomplished with homebrew:

.. code-block:: bash

    brew cask install vagrant

For Ubuntu 16.04, download the vagrant .dpkg directly from
https://vagrantup.com.  The one that ships with Ubuntu is too old.

Setup Vagrant VMs
-----------------

From your BMO checkout run the following command:

.. code-block:: bash

    vagrant up

Depending on the speed of your computer and your Internet connection, this
will take from a few minutes to much longer.

If this fails, please file a bug `using this link <https://bugzilla.mozilla.org/enter_bug.cgi?assigned_to=nobody%40mozilla.org&bug_file_loc=http%3A%2F%2F&bug_ignored=0&bug_severity=normal&bug_status=NEW&cf_fx_iteration=---&cf_fx_points=---&component=Developer%20Box&contenttypemethod=autodetect&contenttypeselection=text%2Fplain&defined_groups=1&flag_type-254=X&flag_type-4=X&flag_type-607=X&flag_type-791=X&flag_type-800=X&flag_type-803=X&form_name=enter_bug&maketemplate=Remember%20values%20as%20bookmarkable%20template&op_sys=Unspecified&priority=--&product=bugzilla.mozilla.org&rep_platform=Unspecified&target_milestone=---&version=Production>`__.

Otherwise, you should have a working BMO developer machine!

To test it, you'll want to add an entry to /etc/hosts for bmo-web.vm pointing
to 192.168.3.43.

After that, you should be able to visit http://bmo-web.vm/ from your browser.
You can login as vagrant@bmo-web.vm with the password "vagrant01!" (without
quotes).

Making Changes and Seeing them
------------------------------

After editing files in the bmo directory, you will need to run

.. code-block:: bash

    vagrant rsync && vagrant provision --provision-with update

to see the changes applied to your vagrant VM. If the above command fails
or db is changed, do a full provision:

.. code-block:: bash

    vagrant rsync && vagrant provision

If you are using Visual Studio Code, these commands will come in handy as the
editor's `tasks`_ that can be found under the Terminal menu. The update command
can be executed by simply hitting `Ctrl+Shift+B` on Windows/Linux or
`Command+Shift+B` on macOS. An `extension bundle`_ for VS Code is also available.

.. _`tasks`: https://code.visualstudio.com/docs/editor/tasks
.. _`extension bundle`: https://marketplace.visualstudio.com/items?itemName=dylanwh.bugzilla

Testing Auth delegation
-----------------------

For testing auth-delegation there is included an `scripts/auth-test-app`
script that runs a webserver and implements the auth delegation protocol.

Provided you have `Mojolicious`_ installed:

.. code-block:: bash
  perl auth-test-app daemon

Then just browse to `localhost:3000`_ to test creating API keys.

.. _`Mojolicious`: https://metacpan.org/pod/Mojolicious
.. _`localhost:3000`: http://localhost:3000

Technical Details
-----------------

This Vagrant environment is a very complete but scaled-down version of
production BMO.  It uses roughly the same RPMs (from CentOS 6, versus RHEL 6
in production) and the same perl dependencies (via
https://github.com/mozilla-bteam/carton-bundles).

It includes a couple example products, some fake users, and some of BMO's
real groups. Email is disabled for all users; however, it is safe to enable
email as the box is configured to send all email to the 'vagrant' user on the
web vm.

Most of the cron jobs and the jobqueue daemon are running.  It is also
configured to use memcached.

The push connector is not currently configured, nor is the Pulse publisher.


Perl Shell (re.pl, repl)
------------------------

Installed on the vagrant vm is also a program called re.pl.

re.pl an interactive perl shell (somtimes called a REPL (short for Read-Eval-Print-Loop)).
It loads Bugzilla.pm and you can call Bugzilla internal API methods from it, an example session is reproduced below:

.. code-block:: plain

   re.pl
   $ my $product = Bugzilla::Product->new({name => "Firefox"});
   Took 0.0262260437011719 seconds.

   $Bugzilla_Product1 = Bugzilla::Product=HASH(0x7e3c950);

   $ $product->name
   Took 0.000483036041259766 seconds.

   Firefox

It supports tab completion for file names, method names and so on. For more information see `Devel::REPL`_.

You can use the 'p' command (provided by `Data::Printer`_) to inspect variables as well.

.. code-block:: plain

  $ p @INC
  [
      [0]  ".",
      [1]  "lib",
      [2]  "local/lib/perl5/x86_64-linux-thread-multi",
      [3]  "local/lib/perl5",
      [4]  "/home/vagrant/perl/lib/perl5/x86_64-linux-thread-multi",
      [5]  "/home/vagrant/perl/lib/perl5",
      [6]  "/vagrant/local/lib/perl5/x86_64-linux-thread-multi",
      [7]  "/vagrant/local/lib/perl5",
      [8]  "/usr/local/lib64/perl5",
      [9]  "/usr/local/share/perl5",
      [10] "/usr/lib64/perl5/vendor_perl",
      [11] "/usr/share/perl5/vendor_perl",
      [12] "/usr/lib64/perl5",
      [13] "/usr/share/perl5",
      [14] sub { ... }
  ]

.. _`Devel::REPL`: https://metacpan.org/pod/Devel::REPL
.. _`Data::Printer`: https://metacpan.org/pod/Data::Printer


Using Docker (For Development)
==============================

While not yet as featureful or complete as the vagrant setup, this repository now contains a
docker-compose file that will create a local bugzilla for testing.

To use docker-compose, ensure you have the latest Docker install for your environemnt
(Linux, Windows, or Mac OS). If you are using Ubuntu, then you can read the next section
to ensure that you have the correct docker setup.

.. code-block:: bash

    docker-compose up --build


Then, you must configure your browser to use http://localhost:1091 as an HTTP proxy.
For setting a proxy in Firefox, see `Firefox Connection Settings`_.
The procecure should be similar for other browsers.

.. _`Firefox Connection Settings`: https://support.mozilla.org/en-US/kb/connection-settings-firefox

After that, you should be able to visit http://bmo-web.vm/ from your browser.
You can login as vagrant@bmo-web.vm with the password "vagrant01!" (without
quotes).

Ensuring your Docker setup on Ubuntu 16.04
==========================================

On Ubuntu, Docker can be installed using apt-get. After installing, you need to do run these
commands to ensure that it has installed fine:

.. code-block:: bash

    sudo groupadd docker # add a new group called "docker"
    sudo gpasswd -a <your username> docker # add yourself to "docker" group

Log in & log out of your system, so that changes in the above commands will  & do this:

.. code-block:: bash

    sudo service docker restart
    docker run hello-world

If the output of last command looks like this. then congrats you have installed
docker successfully:

.. code-block:: bash

    Hello from Docker!
    This message shows that your installation appears to be working correctly.

Docker Container
================

This repository is also a runnable docker container.

Container Arguments
-------------------

Currently, the entry point takes a single command argument.
This can be **httpd** or **shell**.

httpd
    This will start apache listening for connections on ``$PORT``
shell
    This will start an interactive shell in the container. Useful for debugging.


Environmental Variables
-----------------------

PORT
  This must be a value >= 1024. The httpd will listen on this port for incoming
  plain-text HTTP connections.
  Default: 8000

MOJO_REVERSE_PROXY
  This tells the backend that it is behind a proxy.
  Default: 1

MOJO_HEARTBEAT_INTERVAL
  How often (in seconds) will the manager process send a heartbeat to the workers.
  Default: 10

MOJO_HEARTBEAT_TIMEOUT
  Maximum amount of time in seconds before a worker without a heartbeat will be stopped gracefully
  Default: 120

MOJO_INACTIVITY_TIMEOUT
  Maximum amount of time in seconds a connection can be inactive before getting closed.
  Default: 120

MOJO_WORKERS
  Number of worker processes. A good rule of thumb is two worker processes per
  CPU core for applications that perform mostly non-blocking operations,
  blocking operations often require more and benefit from decreasing
  concurrency with "MOJO_CLIENTS" (often as low as 1). Note that during zero
  downtime software upgrades there will be twice as many workers active for a
  short amount of time.
  Default: 1

MOJO_SPARE
  Temporarily spawn up to this number of additional workers if there is a
  need. This allows for new workers to be started while old ones are still
  shutting down gracefully, drastically reducing the performance cost of
  worker restarts.
  Default: 1

MOJO_CLIENTS
  Maximum number of accepted connections each worker process is allowed to
  handle concurrently, before stopping to accept new incoming connections. Note
  that high concurrency works best with applications that perform mostly
  non-blocking operations, to optimize for blocking operations you can decrease
  this value and increase "MOJO_WORKERS" instead for better performance.
  Default: 200

BUGZILLA_UNSAFE_AUTH_DELEGATION
  This should never be set in production. It allows auth delegation over http.

BMO_urlbase
  The public url for this instance. Note that if this begins with https://
  and BMO_inbound_proxies is set to '*' Bugzilla will believe the connection to it
  is using SSL.

BMO_canonical_urlbase
  The public url for the production instance, if different from urlbase above.

BMO_attachment_base
  This is the url for attachments.
  When the allow_attachment_display parameter is on, it is possible for a
  malicious attachment to steal your cookies or perform an attack on Bugzilla
  using your credentials.

  If you would like additional security on attachments to avoid this, set this
  parameter to an alternate URL for your Bugzilla that is not the same as
  urlbase or sslbase. That is, a different domain name that resolves to this
  exact same Bugzilla installation.

  For added security, you can insert %bugid% into the URL, which will be
  replaced with the ID of the current bug that the attachment is on, when you
  access an attachment. This will limit attachments to accessing only other
  attachments on the same bug. Remember, though, that all those possible domain
  names (such as 1234.your.domain.com) must point to this same Bugzilla
  instance.

BMO_db_driver
  What SQL database to use. Default is mysql. List of supported databases can be
  obtained by listing Bugzilla/DB directory - every module corresponds to one
  supported database and the name of the module (before ".pm") corresponds to a
  valid value for this variable.

BMO_db_host
  The DNS name or IP address of the host that the database server runs on.

BMO_db_name
  The name of the database.

BMO_db_user
  The database user to connect as.

BMO_db_pass
  The password for the user above.

BMO_site_wide_secret
  This secret key is used by your installation for the creation and
  validation of encrypted tokens. These tokens are used to implement
  security features in Bugzilla, to protect against certain types of attacks.
  It's very important that this key is kept secret.

BMO_inbound_proxies
  This is a list of IP addresses that we expect proxies to come from.
  This can be '*' if only the load balancer can connect to this container.
  Setting this to '*' means that BMO will trust the X-Forwarded-For header.

BMO_memcached_namespace
  The global namespace for the memcached servers.

BMO_memcached_servers
  A list of memcached servers (ip addresses or host names). Can be empty.

BMO_shadowdb
  The database name of the read-only database.

BMO_shadowdbhost
  The hotname or ip address of the read-only database.

BMO_shadowdbport
   The port of the read-only database.

BMO_setrlimit
    This is a json object and can set any limit described in https://metacpan.org/pod/BSD::Resource.
    Typically it used for setting RLIMIT_AS, and the default value is ``{ "RLIMIT_AS": 2000000000 }``.

BMO_size_limit
  This is the max amount of unshared memory the worker processes are allowed to
  use before they will exit. Minimum 750000 (750MiB)

BMO_mail_delivery_method
  Usually configured on the MTA section of admin interface, but may be set here for testing purposes.
  Valid values are None, Test, Sendmail, or SMTP.
  If set to Test, email will be appended to the /app/data/mailer.testfile.

BMO_use_mailer_queue
  Usually configured on the MTA section of the admin interface, you may change this here for testing purposes.
  Should be 1 or 0. If 1, the job queue will be used. For testing, only set to 0 if the BMO_mail_delivery_method is None or Test.

USE_NYTPROF
  Write `Devel::NYTProf`_ profiles out for each requests.
  These will be named /app/data/nytprof.$host.$script.$n.$pid, where $host is
  the hostname of the container, script is the name of the script (without
  extension), $n is a number starting from 1 and incrementing for each
  request to the worker process, and $pid is the worker process id.

NYTPROF_DIR
  Alternative location to store profiles from the above option.

LOG4PERL_CONFIG_FILE
  Filename of `Log::Log4perl`_ config file.
  It defaults to log4perl-syslog.conf.
  If the file is given as a relative path, it will belative to the /app/conf/ directory.

.. _`Devel::NYTProf`: https://metacpan.org/pod/Devel::NYTProf
.. _`Log::Log4perl`: https://metacpan.org/pod/Log::Log4perl

LOG4PERL_STDERR_DISABLE
  Boolean. By default log messages are logged as plain text to `STDERR`.
  Setting this to a true value disables this behavior.

  Note: For programs that run using the `cereal` log aggregator, this environemnt
  variable will be ignored.

Persistent Data Volume
----------------------

This container expects /app/data to be a persistent, shared, writable directory
owned by uid 10001. This must be a shared (NFS/EFS/etc) volume between all
nodes.

Development Tips
================

Testing Emails
--------------

With vagrant have two options to test emails sent by a local bugzilla instance. You can configure
which setting you want to use by going to http://bmo-web.vm/editparams.cgi?section=mta and
changing the mail_delivery_method to either 'Test' or 'Sendmail'. Afterwards restart bmo with
``vagrant reload``. With docker, only the default 'Test' option is supported.

'Test' option (Default for Docker)
~~~~~~~~~~~~~~~~~~~~~~~

With this option, all mail will be appended to a ``mailer.testfile``.

- Using docker, run ``docker-compose run bmo-web.vm cat /app/data/mailer.testfile``.
- Using vagrant, run ``vagrant ssh web`` and then naviage to ``/vagrant/data/mailer.testfile``.

'Sendmail' option (Default for Vagrant)
~~~~~~~~~~~~~~~~~

This option is useful if you want to preview email using a real mail client.
An imap server is running on bmo-web.vm on port 143 and you can connect to it with
the following settings:

- host: bmo-web.vm
- port: 143
- encryption: No SSL, Plaintext password
- username: vagrant
- password: anything

All email that bmo sends will go to the vagrant user, so there is no need to login with
multiple imap accounts.

`Thunderbird's`_ wizard to add a new "Existing Mail Account" doesn't work with bmo-web. It
fails because it wants to create a mail account with both incoming mail (IMAP) and outgoing
mail (SMTP, which bmo-web.vm doesn't provide). To work around this, using a regular email
account to first setup, then modify the settings of that account: Right Click the account in
the left side bar > Settings > Server Settings. Update the server settings to match those
listed above. Afterwards, you may update the account name to be vagrant@bmo-web.vm. Thunderbird
will now pull email from bmo. You can try it out by commenting on a bug.

.. _`Thunderbird's`: https://www.mozilla.org/en-US/thunderbird/
