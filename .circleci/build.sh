#!/bin/bash

set -euf -o pipefail

docker build \
    --build-arg CI="$CI" \
    --build-arg CIRCLE_SHA1="$CIRCLE_SHA1" \
    --build-arg CIRCLE_BUILD_URL="$CIRCLE_BUILD_URL" \
    -t bmo .

docker run --name bmo --entrypoint true bmo
docker cp bmo:/app/version.json build_info/version.json
