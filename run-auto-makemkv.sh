#!/usr/bin/env bash

set -e

# Build off the git repo.
docker build \
  -t auto-makemkv \
  https://github.com/redeemed2011/makemkv.git

# Run the container. It should attempt to execute MakeMKV on the device then self-destruct.
docker run --rm \
  --device=/dev/cdrom \
  -e MKV_GID=$(id -g ${USER}) \
  -e MKV_UID=$(id -u ${USER}) \
  -v /data/makemkv:/output \
  auto-makemkv
