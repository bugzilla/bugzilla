Docker Bugzilla
===============

Configure a running Bugzilla system using Docker

## Features

* Running latest Centos
* Preconfigured with initial data and test product
* Running Apache2 and MySQL Community Server 5.6
* Openssh server so you can ssh in to the system to make changes
* Code resides in `/home/bugzilla/devel/htdocs/bmo` and can be updated,
  diffed, and branched using standard git commands

## How to install Docker and Fig

### Linux

1. Visit [Docker][docker] and get docker up and running on your system.

2. Visit [Fig][fig] to install Fig for managing Docker containers.

### OSX

1. Visit [Docker][docker] and get docker up and running on your system.

2. Visit [Fig][fig] to install Fig for managing multiple related Docker containers.

3. Start boot2docker in a terminal once it is installed. Ensure that you run the
 export DOCKER_HOST=... lines when prompted:

```bash
$ boot2docker start
$ export DOCKER_HOST=tcp://192.168.59.103:2375
```

### Windows

1. Install the [Windows boot2docker installer][windows]
2. Run the "Boot2Docker Start" shortcut on the startmenu (this inits the VM,
   starts it and connects to it)
3. Run the following in the boot2docker VM as a one-off:

```bash
echo 'alias fig='"'"'docker run --rm -it \
        -v $(pwd):/app \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -e FIG_PROJECT_NAME=$(basename $(pwd)) \
        dduportal/fig'"'" >> /home/docker/.ashrc
```

4. Logout from the VM (ctrl+D)

Then all you need to do on later occasions is:

1. Re-run "Boot2Docker Start" or from the console just enter:

```bash
boot2docker start && boot2docker ssh
```

2. cd `/c/Users/Username/src/bmo/docker` (paths under c:\Users are
   automatically mapped by boot2docker from the client into the VM)
3. `fig build` (and so on)`

## Important boot2docker Notes

Due to an issue with installation of certain packages in Centos7 and the
default storage driver (AUFS) used by boot2docker, we need to change the
driver to `devicemapper` for the image build process to complete properly.

To do so, once you have boot2docker installed and the VM running, but before
performing the build process, do:

```bash
$ boot2docker ssh
Boot2Docker version 1.4.1, build master : 86f7ec8 - Tue Dec 16 23:11:29 UTC 2014
Docker version 1.4.1, build 5bc2ff8
docker@boot2docker:~$ echo 'EXTRA_ARGS="--storage-driver=devicemapper"' | sudo tee -a /var/lib/boot2docker/profile
docker@boot2docker:~$ sudo /etc/init.d/docker restart
```

Also before building, you will need to change value in the
`checksetup_answers.txt` file to match the IP address of the boot2docker VM.
You can find the IP address by running `boot2docker ip`.

For example, using a text editor, change the following line in
`checksetup_answers.txt` from:

` $answer{'urlbase'} = 'http://localhost:8080/bmo/';`

to

` $answer{'urlbase'} = 'http://192.168.59.103:8080/bmo/';`

## How to build Bugzilla Docker image

To build a fresh image, just change to the directory containing the checked out
files and run the below command:

```bash
$ fig build
```

## How to start Bugzilla Docker image

To start a new container (or rerun your last container) you simply do:

```bash
$ fig up
```

This will stay in the foreground and you will see the output from `supervisord`. You
can use the `-d` option to run the container in the background.

To stop, start or remove the container that was created from the last run, you can do:

```bash
$ fig stop
$ fig start
$ fig rm
```

## How to access the Bugzilla container

If you are using Linux, you can simply point your browser to
`http://localhost:8080/bmo` to see the the Bugzilla home page.

If using boot2docker, you will need to use the IP address of the VM. You can
find the IP address using the `boot2docker ip` command. For example:

```bash
$ boot2docker ip
192.168.59.103

```

So would then point your browser to `http://192.168.59.103:8080/bmo`.

The Administrator username is `admin@mozilla.bugs` and the password is `password`.
You can use the Administrator account to creat other users, add products or
components, etc.

You can also ssh into the container using `ssh bugzilla@localhost -p2222` command.
The password  is `bugzilla`. You can run multiple containers but you will need
to give each one a different name/hostname as well as non-conflicting ports
numbers for ssh and httpd.

## TODO

* Update `generate_bmo_data.pl` to include more sample products, groups and
settings to more closely match bugzilla.mozilla.org.
* Enable SSL support.
* Enable memcached

[docker]: https://docs.docker.com/installation/
[windows]: http://docs.docker.com/installation/windows/
[fig]: http://www.fig.sh
[vagrant]: https://docs.vagrantup.com/v2/getting-started/
