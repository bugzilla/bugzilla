=========================
BMO: bugzilla.mozilla.org
=========================

BMO is Mozilla's highly customized version of Bugzilla.

.. image:: https://circleci.com/gh/mozilla-bteam/bmo/tree/master.svg?style=svg
    :target: https://circleci.com/gh/mozilla-bteam/bmo/tree/master

.. contents::
..
    1.  Using Docker Compose (For Development)
    2.  Docker Container
      2.1  Container Arguments
      2.2  Environmental Variables
      2.3  Logging Configuration
      2.4  Persistent Data Volume
    3. Development Tips
      3.1  Testing Emails
    4. Administrative Tasks
      4.1  Generating cpanfile and cpanfile.snapshot files
      4.2  Generating a new mozillabteam/bmo-perl-slim base image

If you want to contribute to BMO, you can fork this repo and get a local copy
of BMO running in a few minutes using Docker.


Using Docker (For Development)
==============================

This repository contains a docker-compose file that will create a local Bugzilla for testing.

To use docker-compose, ensure you have the latest Docker install for your environment
(Linux, Windows, or Mac OS). If you are using Ubuntu, then you can read the next section
to ensure that you have the correct docker setup.

.. code-block:: bash

    docker-compose up --build

Then, you must configure your browser to use localhost and port 1080 as an HTTP proxy.
For setting a proxy in Firefox, see `Firefox Connection Settings`_.
The procedure should be similar for other browsers.

.. _`Firefox Connection Settings`: https://support.mozilla.org/en-US/kb/connection-settings-firefox

After that, you should be able to visit http://bmo.test/ from your browser.
You can login as admin@bmo.test with the password "password01!" (without
quotes).

If you want to update the code running in the web container, you do not need to restart everything.
You can run the following command:

.. code-block:: bash

    docker-compose exec bmo.test rsync -avz --exclude .git --exclude local /mnt/sync/ /app/

The Mojolicious morbo development server, used by the web container, will notice any code changes and
restart itself.

If you are using Visual Studio Code, these ``docker-compose`` commands will come in handy as the
editor's `tasks`_ that can be found under the Terminal menu. The update command is assigned to the
default build task so it can be executed by simply hitting Ctrl+Shift+B on Windows/Linux or
Command+Shift+B on macOS. An `extension bundle`_ for VS Code is also available.

.. _`tasks`: https://code.visualstudio.com/docs/editor/tasks
.. _`extension bundle`: https://marketplace.visualstudio.com/items?itemName=dylanwh.bugzilla


Ensuring your Docker setup on Ubuntu 16.04
------------------------------------------

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

BUGZILLA_ALLOW_INSECURE_HTTP
  This should never be set in production. It allows auth delegation and oauth over http.

BMO_urlbase
  The public URL for this instance. Note that if this begins with https://
  and BMO_inbound_proxies is set to '*' Bugzilla will believe the connection to it
  is using SSL.

BMO_canonical_urlbase
  The public URL for the production instance, if different from urlbase above.

BMO_attachment_base
  This is the URL for attachments.
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

BMO_jwt_secret
  This secret key is used by your installation for the creation and validation
  of jwts.  It's very important that this key is kept secret and it should be
  different from the side_wide_secret. Changing this will invalidate all issued
  jwts, so all oauth clients will need to start over. As such it should be a
  high level of entropy, as it probably won't change for a very long time.

BMO_inbound_proxies
  This is a list of IP addresses that we expect proxies to come from.
  This can be '*' if only the load balancer can connect to this container.
  Setting this to '*' means that BMO will trust the X-Forwarded-For header.

BMO_memcached_namespace
  The global namespace for the memcached servers.

BMO_memcached_servers
  A list of memcached servers (IP addresses or host names). Can be empty.

BMO_shadowdb
  The database name of the read-only database.

BMO_shadowdbhost
  The hotname or IP address of the read-only database.

BMO_shadowdbport
   The port of the read-only database.

BMO_setrlimit
    This is a JSON object and can set any limit described in https://metacpan.org/pod/BSD::Resource.
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
  If the file is given as a relative path, it will relative to the /app/conf/ directory.

.. _`Devel::NYTProf`: https://metacpan.org/pod/Devel::NYTProf

.. _`Log::Log4perl`: https://metacpan.org/pod/Log::Log4perl

LOG4PERL_STDERR_DISABLE
  Boolean. By default log messages are logged as plain text to `STDERR`.
  Setting this to a true value disables this behavior.

  Note: For programs that run using the `cereal` log aggregator, this environment
  variable will be ignored.


Logging Configuration
---------------------

How Bugzilla logs is entirely configured by the environmental variable
`LOG4PERL_CONFIG_FILE`.  This config file should be familiar to someone
familiar with log4j, and it is extensively documented in `Log::Log4perl`_.

Many examples are provided in the logs/ directory.

If multiple processes will need to log, it should be configured to log to a socket on port 5880.
This will be the "cereal" daemon, which will only be started for jobqueue and httpd-type containers.

The example log config files will often be configured to log to stderr
themselves.  To prevent duplicate lines (or corrupted log messages), stderr
logging should be filtered on the existence of the LOG4PERL_STDERR_DISABLE
environmental variable.

Logging configuration also controls which errors are sent to Sentry.


Persistent Data Volume
----------------------

This container expects /app/data to be a persistent, shared, writable directory
owned by uid 10001. This must be a shared (NFS/EFS/etc) volume between all
nodes.


Development Tips
================

Testing Emails
--------------

Configure your MTA setting you want to use by going to http://bmo.test/editparams.cgi?section=mta
and changing the mail_delivery_method to 'Test'. With this option, all mail will be appended to a
``data/mailer.testfile``. To see the emails being sent:

.. code-block:: bash

  docker-compose run bmo.test cat /app/data/mailer.testfile

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

This Docker environment is a very scaled-down version of production BMO.
It uses roughly the same Perl dependencies as production. It is also
configured to use memcached. The push connector is running but is not
currently configured, nor is the Phabricator feed daemon.

It includes a couple example products, some fake users, and some of BMO's
real groups. Email is disabled for all users; however, it is safe to enable
email as the box is configured to send all email to the 'admin' user on the
web vm.


Administrative Tasks
====================

Generating cpanfile and cpanfile.snapshot files
-----------------------------------------------

.. code-block:: bash

  docker build -t bmo-cpanfile -f Dockerfile.cpanfile .
  docker run -it -v "$(pwd):/app/result" bmo-cpanfile cp cpanfile cpanfile.snapshot /app/result

Generating a new mozillabteam/bmo-perl-slim base image
------------------------------------------------------

The mozillabteam/bmo-perl-slim image is stored in the Mozilla B-Team
Docker Hub repository. It contains just the Perl dependencies in ``/app/local``
and other Debian packages needed. Whenever the ``cpanfile`` and
``cpanfile.snapshot`` files have been changed by the above steps after a
succcessful merge, a new mozillabteam/bmo-perl-slim image will need to be
built and pushed to Docker Hub.

A Docker Hub organization administrator with the correct permissions will
normally do the ``docker login`` and ``docker push``.

The ``<DATE>`` value should be the current date in ``YYYYMMDD.X``
format with X being the current iteration value. For example, ``20191209.1``.

.. code-block:: bash

  docker build -t mozillabteam/bmo-perl-slim:<DATE> -f Dockerfile.bmo-slim .
  docker login
  docker push mozillabteam/bmo-perl-slim:<DATE>

After pushing to Docker Hub, you will need to update ``Dockerfile`` to include the new
built image with correct date. Create a PR, review and commit the new change.
