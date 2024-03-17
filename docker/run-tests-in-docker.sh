#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

if [ ! -e 'Makefile.PL' ]; then
    echo
    echo "Please run this from the root of the Bugzilla source tree."
    echo
    exit -1
fi
if [ -z "$DOCKER" ]; then
    DOCKER=`which docker`
fi
if [ ! -x "$DOCKER" ]; then
    echo
    echo "You specified a custom Docker executable via the DOCKER"
    echo "environment variable at $DOCKER"
    echo "which either does not exist or is not executable."
    echo "Please fix it to point at a working Docker or remove the"
    echo "DOCKER environment variable to use the one in your PATH"
    echo "if it exists."
    echo
    exit -1
fi
if [ -z "$DOCKER" ]; then
    echo
    echo "You do not appear to have docker installed or I can't find it."
    echo "Windows and Mac versions can be downloaded from"
    echo "https://www.docker.com/products/docker-desktop"
    echo "Linux users can install using your package manager."
    echo
    echo "Please install docker or specify the location of the docker"
    echo "executable in the DOCKER environment variable and try again."
    echo
    exit -1
fi
$DOCKER info 1>/dev/null 2>/dev/null
if [ $? != 0 ]; then
    echo
    echo "The docker daemon is not running or I can't connect to it."
    echo "Please make sure it's running and try again."
    echo
    exit -1
fi

export DOCKER_CLI_HINTS=false
export CI=""
export CIRCLE_SHA1=""
export CIRCLE_BUILD_URL=""
$DOCKER compose -f docker-compose.test.yml build
if [ $? == 0 ]; then
    $DOCKER compose -f docker-compose.test.yml run bmo.test test_bmo -q -f t/bmo/*.t
else
    echo "docker compose build failed."
fi
