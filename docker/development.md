# Using Docker (For Development)

This repository contains a docker-compose file that will create a local
Bugzilla for testing.

To use docker-compose, ensure you have the latest Docker install for
your environment (Linux, Windows, or Mac OS). If you are using Ubuntu,
then you can read the next section to ensure that you have the correct
docker setup.

``` bash
docker-compose up --build
```

Then, you must configure your browser to use localhost and port 1080 as
an HTTP proxy. For setting a proxy in Firefox, see [Firefox Connection
Settings](https://support.mozilla.org/en-US/kb/connection-settings-firefox).
The procedure should be similar for other browsers.

After that, you should be able to visit <http://bmo.test/> from your
browser. You can login as <admin@bmo.test> with the password
`password01!`.

If you want to update the code running in the web container, you do not
need to restart everything. You can run the following command:

``` bash
docker-compose exec bmo.test rsync -avz --exclude .git --exclude local /mnt/sync/ /app/
```

The Mojolicious morbo development server, used by the web container,
will notice any code changes and restart itself.

If you are using Visual Studio Code, these `docker-compose` commands
will come in handy as the editor's
[tasks](https://code.visualstudio.com/docs/editor/tasks) that can be
found under the Terminal menu. The update command is assigned to the
default build task so it can be executed by simply hitting Ctrl+Shift+B
on Windows/Linux or Command+Shift+B on macOS. An [extension
bundle](https://marketplace.visualstudio.com/items?itemName=dylanwh.bugzilla)
for VS Code is also available.

## Ensuring your Docker setup on Ubuntu 16.04

On Ubuntu, Docker can be installed using apt-get. After installing, you
need to do run these commands to ensure that it has installed fine:

``` bash
sudo groupadd docker # add a new group called "docker"
sudo gpasswd -a <your username> docker # add yourself to "docker" group
```

Log in & log out of your system, so that changes in the above commands
will & do this:

``` bash
sudo service docker restart
docker run hello-world
```

If the output of last command looks like this. then congrats you have
installed docker successfully:

``` bash
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

## Development Environment Testing

### Testing Emails

Configure your MTA setting you want to use by going to
<http://bmo.test/editparams.cgi?section=mta> and changing the
mail\_delivery\_method to 'Test'. With this option, all mail will be
appended to a `data/mailer.testfile`. To see the emails being sent:

``` bash
docker-compose run bmo.test cat /app/data/mailer.testfile
```

### Testing Auth delegation

For testing auth-delegation there is included an `scripts/auth-test-app`
script that runs a webserver and implements the auth delegation
protocol.

Provided you have [Mojolicious](https://metacpan.org/pod/Mojolicious)
installed:

``` bash
perl auth-test-app daemon
```

Then just browse to [localhost:3000](http://localhost:3000) to test
creating API keys.

### Technical Details

This Docker environment is a very scaled-down version of production BMO.
It uses roughly the same Perl dependencies as production. It is also
configured to use memcached. The push connector is running but is not
currently configured, nor is the Phabricator feed daemon.

It includes a couple example products, some fake users, and some of
BMO's real groups. Email is disabled for all users; however, it is safe
to enable email as the box is configured to send all email to the
'admin' user on the web vm.
