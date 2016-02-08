Docker Bugzilla
===============

Configure a running Bugzilla system using Docker

## Features

* Running latest Centos
* Preconfigured with initial data and test product
* Running Apache2 and MySQL Community Server 5.6
* Code resides in `/home/bugzilla/devel/htdocs/bugzilla and can be updated,
  diffed, and branched using standard git commands

## How to install Docker Docker Machine and Docker Compose

* Visit [Docker][docker] and get docker up and running on your system.

## Important docker Notes

Before building, you will need to change value in the checksetup_answers.txt`
file to match the IP address of the Docker Machine VM. You can find the IP
address by running `docker-machine ip`.

For example, using a text editor, change the following line in
`checksetup_answers.txt` from:

` $answer{'urlbase'} = 'http://localhost:8080/bugzilla/';`

to

` $answer{'urlbase'} = 'http://192.168.59.103:8080/bugzilla/';`

## How to build Bugzilla Docker image

To build a fresh image, just change to the directory containing the checked out
files and run the below command:

```bash
$ docker-compose build
```

## How to start Bugzilla Docker image

To start a new container (or rerun your last container) you simply do:

```bash
$ docker-compose up
```

This will stay in the foreground and you will see the output from `supervisord`. You
can use the `-d` option to run the container in the background.

To stop, start or remove the container that was created from the last run, you can do:

```bash
$ docker-compose stop
$ docker-compose start
$ docker-compose rm
```

## How to access the Bugzilla container

If you are using Linux, you can simply point your browser to
`http://localhost:8080/bugzilla` to see the the Bugzilla home page.

If using Docker Machine, you will need to use the IP address of the VM. You can
find the IP address using the `docker-machine ip` command. For example:

```bash
$ docker-machine ip
192.168.59.103
```

So would then point your browser to `http://192.168.59.103:8080/bugzilla`.

The Administrator username is `admin@bugzilla.org` and the password is `password`.
You can use the Administrator account to creat other users, add products or
components, etc.

You can also shell into the container using `docker exec` command. You will need to
determine the container name or ID of the running container. Here is an example:

```bash
$ docker ps
CONTAINER ID  IMAGE            COMMAND                 CREATED         STATUS         PORTS                           NAMES
2522438509d3  master_bugzilla  "/usr/bin/supervisord"  38 seconds ago  Up 37 seconds  5900/tcp, 0.0.0.0:8080->80/tcp  master_bugzilla_1
$ docker exec -it master_bugzilla_1 su - bugzlla
Last login: Thu Jan 21 14:24:06 UTC 2016
[bugzilla@2522438509d3 ~]$
```

## TODO

* Enable SSL support.

[docker]: https://docs.docker.com/installation/
