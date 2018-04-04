#!/bin/bash

set -euf -o pipefail

[[ -n "$DOCKERHUB_REPO" && -n "$DOCKER_USER" && -n "$DOCKER_PASS" ]] || exit 0
docker login -u "$DOCKER_USER" -p "$DOCKER_PASS"

if [[ "$CIRCLE_BRANCH" == "master" ]]; then
    TAG="$(cat /app/build_info/tag.txt)"
    [[ -n "$GITHUB_PERSONAL_TOKEN" ]] || exit 0
    if [[ -n "$TAG" && -f build_info/publish.txt ]]; then
    git config credential.helper "cache --timeout 120"
    git config user.email "$GITHUB_EMAIL"
    git config user.name "$GITHUB_NAME"
    git tag $TAG
    git push https://${GITHUB_PERSONAL_TOKEN}:x-oauth-basic@github.com/$GITHUB_REPO.git $TAG
    docker tag bmo "$DOCKERHUB_REPO:$TAG"
    docker push "$DOCKERHUB_REPO:$TAG"
    fi
    docker tag bmo "$DOCKERHUB_REPO:latest"
    docker push "$DOCKERHUB_REPO:latest"
elif [[ "$CIRCLE_BRANCH" == "development" ]]; then
    docker tag bmo "$DOCKERHUB_REPO:build-${CIRCLE_BUILD_NUM}"
    docker push "$DOCKERHUB_REPO:build-${CIRCLE_BUILD_NUM}"
fi
