# Docker

This repository is also a runnable docker container.

## Container Arguments

Currently, the entry point takes a single command argument. This can be
**httpd** or **shell**.

  - httpd  
    This will start apache listening for connections on `$PORT`

  - shell  
    This will start an interactive shell in the container. Useful for
    debugging.

## Environmental Variables

  - PORT  
    This must be a value \>= 1024. The httpd will listen on this port
    for incoming plain-text HTTP connections. Default: 8000

  - MOJO\_REVERSE\_PROXY  
    This tells the backend that it is behind a proxy. Default: 1

  - MOJO\_HEARTBEAT\_INTERVAL  
    How often (in seconds) will the manager process send a heartbeat to
    the workers. Default: 10

  - MOJO\_HEARTBEAT\_TIMEOUT  
    Maximum amount of time in seconds before a worker without a
    heartbeat will be stopped gracefully Default: 120

  - MOJO\_INACTIVITY\_TIMEOUT  
    Maximum amount of time in seconds a connection can be inactive
    before getting closed. Default: 120

  - MOJO\_WORKERS  
    Number of worker processes. A good rule of thumb is two worker
    processes per CPU core for applications that perform mostly
    non-blocking operations, blocking operations often require more and
    benefit from decreasing concurrency with "MOJO\_CLIENTS" (often as
    low as 1). Note that during zero downtime software upgrades there
    will be twice as many workers active for a short amount of time.
    Default: 1

  - MOJO\_SPARE  
    Temporarily spawn up to this number of additional workers if there
    is a need. This allows for new workers to be started while old ones
    are still shutting down gracefully, drastically reducing the
    performance cost of worker restarts. Default: 1

  - MOJO\_CLIENTS  
    Maximum number of accepted connections each worker process is
    allowed to handle concurrently, before stopping to accept new
    incoming connections. Note that high concurrency works best with
    applications that perform mostly non-blocking operations, to
    optimize for blocking operations you can decrease this value and
    increase "MOJO\_WORKERS" instead for better performance. Default:
    200

  - BUGZILLA\_ALLOW\_INSECURE\_HTTP  
    This should never be set in production. It allows auth delegation
    and oauth over http.

  - BMO\_urlbase  
    The public URL for this instance. Note that if this begins with
    <https://> and BMO\_inbound\_proxies is set to '\*' Bugzilla will
    believe the connection to it is using SSL.

  - BMO\_canonical\_urlbase  
    The public URL for the production instance, if different from
    urlbase above.

  - BMO\_attachment\_base  
    This is the URL for attachments. When the allow\_attachment\_display
    parameter is on, it is possible for a malicious attachment to steal
    your cookies or perform an attack on Bugzilla using your
    credentials.
    
    If you would like additional security on attachments to avoid this,
    set this parameter to an alternate URL for your Bugzilla that is not
    the same as urlbase or sslbase. That is, a different domain name
    that resolves to this exact same Bugzilla installation.
    
    For added security, you can insert %bugid% into the URL, which will
    be replaced with the ID of the current bug that the attachment is
    on, when you access an attachment. This will limit attachments to
    accessing only other attachments on the same bug. Remember, though,
    that all those possible domain names (such as 1234.your.domain.com)
    must point to this same Bugzilla instance.

  - BMO\_db\_driver  
    What SQL database to use. Default is mysql. List of supported
    databases can be obtained by listing Bugzilla/DB directory - every
    module corresponds to one supported database and the name of the
    module (before ".pm") corresponds to a valid value for this
    variable.

  - BMO\_db\_host  
    The DNS name or IP address of the host that the database server runs
    on.

  - BMO\_db\_name  
    The name of the database.

  - BMO\_db\_user  
    The database user to connect as.

  - BMO\_db\_pass  
    The password for the user above.

  - BMO\_site\_wide\_secret  
    This secret key is used by your installation for the creation and
    validation of encrypted tokens. These tokens are used to implement
    security features in Bugzilla, to protect against certain types of
    attacks. It's very important that this key is kept secret.

  - BMO\_jwt\_secret  
    This secret key is used by your installation for the creation and
    validation of jwts. It's very important that this key is kept secret
    and it should be different from the side\_wide\_secret. Changing
    this will invalidate all issued jwts, so all oauth clients will need
    to start over. As such it should be a high level of entropy, as it
    probably won't change for a very long time.

  - BMO\_inbound\_proxies  
    This is a list of IP addresses that we expect proxies to come from.
    This can be '*' if only the load balancer can connect to this
    container. Setting this to '*' means that BMO will trust the
    X-Forwarded-For header.

  - BMO\_memcached\_namespace  
    The global namespace for the memcached servers.

  - BMO\_memcached\_servers  
    A list of memcached servers (IP addresses or host names). Can be
    empty.

  - BMO\_shadowdb  
    The database name of the read-only database.

  - BMO\_shadowdbhost  
    The hotname or IP address of the read-only database.

  - BMO\_shadowdbport  
    The port of the read-only database.

  - BMO\_setrlimit  
    This is a JSON object and can set any limit described in
    <https://metacpan.org/pod/BSD>::Resource. Typically it used for
    setting RLIMIT\_AS, and the default value is `{
    "RLIMIT_AS": 2000000000 }`.

  - BMO\_size\_limit  
    This is the max amount of unshared memory the worker processes are
    allowed to use before they will exit. Minimum 750000 (750MiB)

  - BMO\_mail\_delivery\_method  
    Usually configured on the MTA section of admin interface, but may be
    set here for testing purposes. Valid values are None, Test,
    Sendmail, or SMTP. If set to Test, email will be appended to the
    /app/data/mailer.testfile.

  - BMO\_use\_mailer\_queue  
    Usually configured on the MTA section of the admin interface, you
    may change this here for testing purposes. Should be 1 or 0. If 1,
    the job queue will be used. For testing, only set to 0 if the
    BMO\_mail\_delivery\_method is None or Test.

  - USE\_NYTPROF  
    Write [Devel::NYTProf](https://metacpan.org/pod/Devel::NYTProf)
    profiles out for each requests. These will be named
    /app/data/nytprof.$host.$script.$n.$pid, where $host is the hostname
    of the container, script is the name of the script (without
    extension), $n is a number starting from 1 and incrementing for each
    request to the worker process, and $pid is the worker process id.

  - NYTPROF\_DIR  
    Alternative location to store profiles from the above option.

  - LOG4PERL\_CONFIG\_FILE  
    Filename of [Log::Log4perl](https://metacpan.org/pod/Log::Log4perl)
    config file. It defaults to log4perl-syslog.conf. If the file is
    given as a relative path, it will relative to the /app/conf/
    directory.

  - LOG4PERL\_STDERR\_DISABLE  
    Boolean. By default log messages are logged as plain text to
    `STDERR`. Setting this to a true value disables this behavior.
    
    Note: For programs that run using the `cereal` log aggregator, this
    environment variable will be ignored.

## Logging Configuration

How Bugzilla logs is entirely configured by the environmental variable
`LOG4PERL_CONFIG_FILE`. This config file should be familiar to someone
familiar with log4j, and it is extensively documented in
[Log::Log4perl](https://metacpan.org/pod/Log::Log4perl).

Many examples are provided in the logs/ directory.

If multiple processes will need to log, it should be configured to log
to a socket on port 5880. This will be the "cereal" daemon, which will
only be started for jobqueue and httpd-type containers.

The example log config files will often be configured to log to stderr
themselves. To prevent duplicate lines (or corrupted log messages),
stderr logging should be filtered on the existence of the
LOG4PERL\_STDERR\_DISABLE environmental variable.

Logging configuration also controls which errors are sent to Sentry.

## Persistent Data Volume

This container expects /app/data to be a persistent, shared, writable
directory owned by uid 10001. This must be a shared (NFS/EFS/etc) volume
between all nodes.

## Administrative Tasks

### Generating cpanfile and cpanfile.snapshot files

``` bash
docker build -t bmo-cpanfile -f Dockerfile.cpanfile .
docker run -it -v "$(pwd):/app/result" bmo-cpanfile cp cpanfile cpanfile.snapshot /app/result
```

### Generating a new mozillabteam/bmo-perl-slim base image

The mozillabteam/bmo-perl-slim image is stored in the Mozilla B-Team
Docker Hub repository. It contains just the Perl dependencies in
`/app/local` and other Debian packages needed. Whenever the `cpanfile`
and `cpanfile.snapshot` files have been changed by the above steps after
a succcessful merge, a new mozillabteam/bmo-perl-slim image will need to
be built and pushed to Docker Hub.

A Docker Hub organization administrator with the correct permissions
will normally do the `docker login` and `docker push`.

The `<DATE>` value should be the current date in `YYYYMMDD.X` format
with X being the current iteration value. For example, `20191209.1`.

``` bash
docker build -t mozillabteam/bmo-perl-slim:<DATE> -f Dockerfile.bmo-slim .
docker login
docker push mozillabteam/bmo-perl-slim:<DATE>
```

After pushing to Docker Hub, you will need to update `Dockerfile` to
include the new built image with correct date. Create a PR, review and
commit the new change.
