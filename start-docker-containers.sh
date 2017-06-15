#!/usr/bin/env sh

set -e
set -x


if [ -z "${SCRIPTPATH}" ]; then
  SCRIPTPATH="$( cd "$(dirname "$(readlink --canonicalize-missing "$0")")" ; pwd -P )"
  SCRIPTPATH="${SCRIPTPATH%/}"
fi


#----------------------------------------------------------------------------------------------------------------------
# Main

# Wait for /etc/resolv.conf, if it is a link, to resolve.
resolv_target=""
if [ -L /etc/resolv.conf ]; then
  resolv_target="$(readlink '/etc/resolv.conf')"
  while [ ! -e "${resolv_target}" ]; do
    sleep 1s
  done
fi


#----------------------------------------------------------------------------------------------------------------------
# Run Them All

# MY_PUID="$(id -u)"
# MY_PGID="$(id -g)"
#
# export MY_PUID
# export MY_PGID

cd /opt/bb-file-server/

set +e
docker-compose --verbose stop
set -e

docker-compose up -d --remove-orphans
#docker-compose --verbose up -d --remove-orphans

cd -
