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

# Generate mysql root password if it has not already been done.
if [ ! -e '/opt/bb-file-server/.secrets/mysql_root_pass.txt' ]; then
  base64 /dev/urandom | sudo head -c 64 > /opt/bb-file-server/.secrets/mysql_root_pass.txt
fi

# Generate mysql container environment file.
tee /opt/bb-file-server/.secrets/mysql.env <-"EOF" > /dev/null 2>&1
MYSQL_ROOT_PASSWORD=$(cat /opt/bb-file-server/.secrets/mysql_root_pass.txt)
EOF

# Generate a random cookie secret because we don't need to remember it after each reboot. It'll just cause a re-auth.
OAUTH_COOKIE_SECRET="$(base64 /dev/urandom | sudo head -c 64)"
export OAUTH_COOKIE_SECRET

# For general use.
HOSTNAME="$(hostname)"
export HOSTNAME

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
