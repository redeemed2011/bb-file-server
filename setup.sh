#!/usr/bin/env sh

set -e
# set -x


if [ -z "${SCRIPTPATH}" ]; then
  SCRIPTPATH="$( cd "$(dirname "$(readlink --canonicalize-missing "$0")")" ; pwd -P )"
  SCRIPTPATH="${SCRIPTPATH%/}"
fi


# More info: http://unix.stackexchange.com/questions/13751/kernel-inotify-watch-limit-reached
increaseInotifyWatch() {
  echo 'Increasing inotify watches to max...'

  sudo sed -i '/.*max_user_watches.*/d' '/etc/sysctl.conf'
  echo 'fs.inotify.max_user_watches=524288' | sudo tee -a /etc/sysctl.conf
  sudo sysctl -p

  echo 524288 | sudo tee -a /proc/sys/fs/inotify/max_user_watches

  sudo sysctl fs.inotify.max_user_watches=524288

  echo 'Done.'
}

enableSmartmon() {
  echo 'Ensuring smartmon is enabled for each drive...'

  for f in /dev/sd*; do sudo smartctl --smart=on --offlineauto=on --saveauto=on $f; done

  echo 'Done.'
}

setupDataPaths() {
  echo 'Setting up bb-file data paths...'

  sudo chown -R ${USER}: /data

  mkdir -p /data/media/{movies,pictures,shorts,tv\ shows,videos}
  mkdir -p /data/{freshrss,letsencrypt,makemkv,mariadb,oauth-firewall,openvpn-as,plex,portainer,resilio-sync/{config,folders/sync},syncthing/{config,folders},vms}

  # Disable CoW for key folders:
  chattr +C /data/vms

  echo 'Done.'
}

generalSystemSetup() {
  echo 'Installing general packages...'

  # Untested.
  sudo dnf install -y \
    python \
    python-pip

  echo 'Done installing general packages.'


  echo 'Disabling the troublesome firewall...'
  sudo systemctl stop firewalld
  sudo systemctl disable firewalld
  sudo systemctl mask firewalld
  echo 'Done disabling the troublesome firewall.'


  echo "Disabling the troublesome avahi (mdns) so that Plex may use it's own..."
  sudo systemctl stop avahi-daemon.service avahi-daemon.socket
  sudo systemctl disable avahi-daemon.service avahi-daemon.socket
  echo "Done disabling avahi (mdns)."
}

setupDocker() {
  echo 'Setting up docker & docker-compose...'

  # Ensure the versions of docker released prior to "Moby" are removed.
  set +e
  sudo dnf remove -y docker \
    docker-common \
    container-selinux \
    docker-selinux \
    docker-engine
  set -e

  # Install the latest available Docker, Community Edition.
  # https://docs.docker.com/engine/installation/linux/fedora/#install-using-the-repository
  sudo dnf install -y dnf-plugins-core
  sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  sudo dnf makecache fast
  sudo dnf install -y docker-ce

  # Enable the docker service.
  sudo systemctl enable docker
  sudo systemctl start docker

  # Ensure pip is up to date. Only useful if this script is being run after pip has already been installed.
  sudo pip install --upgrade pip

  # Install docker-compose via pip.
  sudo pip install docker-compose

  # Allow all docker containers to cross-communicate; but allow these commands to error, which happens whenever the
  # firewall is disabled.
  #sudo iptables -I INPUT 1 -i docker0 -j ACCEPT
  #sudo firewall-cmd --permanent --zone=FedoraServer --change-interface=docker0
  set +e
  sudo firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 1 -i docker0 -j ACCEPT
  sudo firewall-cmd --reload
  set -e

  echo 'Done setting up docker & docker-compose.'
}

configurePowerButton() {
  echo 'Configuring the system to shutdown when power button is pressed...'

  sudo dnf install -y acpid

  if [ ! -e '/etc/acpi/actions/power.sh-orig' ]; then
    sudo cp -p /etc/acpi/actions/power.sh{,-orig}
  fi
  sudo ln -sf "${SCRIPTPATH}/power-button.sh" /etc/acpi/actions/power.sh

  sudo systemctl enable acpid.service
  sudo systemctl start acpid.service

  echo 'Done configuring the system to shutdown when power button is pressed'
}

runConfigWizard() {
  local userChoice
  local duckdnsSubDomains
  local duckdnsToken
  local letsencryptEmail
  local oauthFirewallRedirectURL
  local oauthFirewallClientID
  local oauthFirewallClientSecret

  printf "\n\nRun configuration? [Y/N] "

  # Bash specific because of "-n N".
  IFS= read -n 1 -r userChoice
  case "${userChoice}" in
    [yY]*)
      # Do nothing.
      ;;
    *)
      return
      ;;
  esac


  # Prompt for DuckDNS values.
  printf "\n\nDuckDNS subdomains value:  (e.g. the 'mysite' of mysite.duckdns.org)\n"
  IFS= read -r duckdnsSubDomains
  printf "\n\nDuckDNS token value:  (log into https://www.duckdns.org to see your token)\n"
  IFS= read -r duckdnsToken

  # Save DuckDNS enironment file.
  tee /opt/bb-file-server/.secrets/duckdns.env <<-EOF > /dev/null 2>&1
SUBDOMAINS=${duckdnsSubDomains}
TOKEN=${duckdnsToken}
EOF


  # Prompt for LetsEncrypt email.
  printf "\n\nEmail address used for LetsEncrypt:\n"
  IFS= read -r letsencryptEmail

  # Save LetsEncrypt enironment file.
  tee /opt/bb-file-server/.secrets/letsencrypt.env <<-EOF > /dev/null 2>&1
EMAIL=${letsencryptEmail}
SUBDOMAINS=${duckdnsSubDomains}
EOF


  # Prompt for OAuth Firewall values.
  printf "\n\nOAuth Firewall redirect URL: (e.g. https://mysite.duckdns.org/oauth2/callback)\n"
  IFS= read -r oauthFirewallRedirectURL
  printf "\n\nOAuth Firewall client ID:\n"
  IFS= read -r oauthFirewallClientID
  printf "\n\nOAuth Firewall client secret:\n"
  IFS= read -r oauthFirewallClientSecret

  # OAuth general config.
  tee /opt/bb-file-server/.secrets/oauth-firewall.env <<-EOF > /dev/null 2>&1
OAUTH_REDIRECT_URL=${oauthFirewallRedirectURL}
OAUTH_CLIENT_ID=${oauthFirewallClientID}
OAUTH_CLIENT_SECRET=${oauthFirewallClientSecret}
EOF


  # OAuth Firewall authorized emails list.
  printf "\n\nPress ENTER when you are ready to open an editor to populate the OAuth Firewall's allowed email addresses file. Put a single email address on each line.\n"
  # Create the file if it does not exist.
  if [ ! -e '/data/oauth-firewall/authorized_emails' ]; then
    sudo tee /data/oauth-firewall/authorized_emails <<-EOF > /dev/null 2>&1
${letsencryptEmail}
EOF
  fi
  # Open an editor.
  sudo nano /data/oauth-firewall/authorized_emails
}

setupBBFileService() {
  echo 'Setting up bb-file-server service...'

  sudo cp bb-file-server.service /usr/lib/systemd/system/bb-file-server.service

  sudo systemctl daemon-reload
  sudo systemctl enable bb-file-server.service
  sudo systemctl restart bb-file-server.service

  echo 'Done setting up bb-file-server service.'
}



increaseInotifyWatch
enableSmartmon
setupDataPaths
generalSystemSetup
configurePowerButton
setupDocker
runConfigWizard
setupBBFileService



sudo cp udev-rules/* /etc/udev/rules.d/

