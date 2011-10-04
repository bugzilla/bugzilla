#!/bin/bash
HOST=`hostname -s`
TAG="current-staging"
[ "$HOST" == "mradm02" -o "$HOST" == "ip-admin02" ] && TAG="current-production"
echo "+ bzr pull --overwrite -rtag:$TAG"
output=`bzr pull --overwrite -rtag:$TAG 2>&1`
echo "$output"
echo "$output" | grep "Now on revision" | sed -e 's/Now on revision //' -e 's/\.$//' | xargs -i{} echo bzr pull --overwrite -r{} \# `date` >> `dirname $0`/cvs-update.log
contrib/fixperms.pl
