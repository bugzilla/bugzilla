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
$DOCKER build -t bugzilla-cpanfile -f Dockerfile.cpanfile .
$DOCKER run -it -v "$(pwd):/app/result" bugzilla-cpanfile cp cpanfile cpanfile.snapshot /app/result

# Figure out the tag name to use for the image. We'll do this by generating
# a code based on today's date, then attempt to pull it from DockerHub. If
# we successfully pull, then it already exists, and we bump the interation
# number on the end.
DATE=`date +"%Y%m%d"`
ITER=1
$DOCKER pull bugzilla/bugzilla-perl-slim:${DATE}.${ITER} >/dev/null 2>/dev/null
while [ $? == 0 ]; do
    # as long as we succesfully pull, keep bumping the number on the end
    ((ITER++))
    $DOCKER pull bugzilla/bugzilla-perl-slim:${DATE}.${ITER} >/dev/null 2>/dev/null
done
$DOCKER build -t bugzilla/bugzilla-perl-slim:${DATE}.${ITER} -f Dockerfile.bmo-slim .
if [ $? == 0 ]; then
    echo
    echo "The build appears to have succeeded. Don't forget to change the FROM line"
    echo "at the top of Dockerfile to use:"
    echo "  bugzilla/bugzilla-perl-slim:${DATE}.${ITER}"
    echo "to make use of this image."
    echo
    # check if the user is logged in
    if [ -z "$PYTHON" ]; then
        PYTHON=`which python`
    fi
    if [ -z "$PYTHON" ]; then
        PYTHON=`which python3`
    fi
    if [ ! -x "$PYTHON" ]; then
        echo "The python executable specified in your PYTHON environment value or your PATH is not executable or I can't find it."
        exit -1
    fi
    AUTHINFO=`$PYTHON -c "import json; print(len(json.load(open('${HOME}/.docker/config.json','r',encoding='utf-8'))['auths']))"`
    if [ $AUTHINFO -gt 0 ]; then
        # user is logged in
        read -p "Do you wish to push to DockerHub? [y/N]: " yesno
        case $yesno in
            [Yy]*)
                echo "Pushing..."
                $DOCKER push bugzilla/bugzilla-perl-slim:${DATE}.${ITER}
                ;;
            *)
                echo "Not pushing. You can just run this script again when you're ready"
                echo "to push. The prior build result is cached."
                ;;
        esac
    fi
else
    echo
    echo "Docker build failed. See output above."
    echo
    exit -1
fi
