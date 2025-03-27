#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. $DIR/lib/color.sh

PUSH="${PUSH:-false}"
LOAD="${LOAD:-false}"
BUILDX_FLAGS="${BUILDX_FLAGS:-}"
path=$PWD

[ -z "$1" ] || path="$(cd "$1" && pwd)"
name=${path##*/}
platform="linux/amd64,linux/arm64"
platformLabel=$(cat "$path/Dockerfile" | grep -i "^label " | awk -F "[ =]*" '{print $2 " " $3}' | grep -w "platform" | cut -d' ' -f2 | sed -e 's/[" ]*//g' | head -n1 || true)
if [ "$platformLabel" != "" ]; then
    platform="$platformLabel"
fi
nocache=
if [ "$PUSH" == true ]; then
	nocache="--no-cache"
fi

tag="1.$(date -u '+%y%m%d').$(date -u '+%H%M' | awk '{print $0+0}')-H$(git rev-parse --short HEAD)"
buildArgs="$nocache --platform=$platform -t ghcr.io/n0rad/$name:$tag -t ghcr.io/n0rad/$name:latest --build-arg=TAG=$tag $load $BUILDX_FLAGS"

if [ "$PUSH" == true ]; then
  echo_bright_red "Building / Pushing $name:$tag"
  docker buildx build $buildArgs --push "$path"
else
  load=
  if [ "$LOAD" == true ]; then
    load="--load"
  fi
  echo_bright_red "Building $name:$tag"
  docker buildx build $buildArgs $load "$path"
fi
