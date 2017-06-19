# Personal File Server

These are a set of notes, configs, and scripts I use for my personal file server. I'm leaving them open to the public just in case there is something useful in here for someone else.

You're welcome to make pull requests if you are so inclined.

## Goals

* data drive array
* btrfs maintenance
* docker management interface?  portainer!
* duckdns
* openvpn-as
* resilio sync
* syncthing
* VM for windows with pcie passthrough support.
* possibly web interface for VMs. (kimchi?)
* Monitorix
* guacamole -- rdp in web page
* plex
* dvd / bluray ripper


## Status

Current OPENVPN issue:
WARNING: Bad encapsulated packet length from peer (18516), which must be > 0 and <= 1627 -- please ensure that --tun-mtu or --link-mtu is equal on both peers -- this condition could also indicate a possible active attack on the TCP link -- [Attempting restart...]

## BTRFS Raid

At the time of this writing, parity level RAIDing was known to corrupt, so we'll use RAID 10. Linux kernel 4.12 is supposed to fix the RAID5/6 corruption.

### Disable CoW for Select Paths

Example how to disable copy-on-write for single files/directories do:

```shell
chattr +C /path
```

### BB-File BTRFS Setup

Create RAID with our drives:

```shell
sudo mkfs.btrfs -m raid10 -d raid10 \
  /dev/sda \
  /dev/sdb \
  /dev/sdc \
  /dev/sdd \
  /dev/sdf \
  /dev/sdg
```

NOTE: Our boot drive was /dev/sde at the time of this writing.

Mount the BTRFS array:

```shell
[ ! -d '/data' ] && sudo mkdir /data
sudo mount /dev/sda /data
```

Update `/etc/fstab` to mount our BTRFS array: (ensure the UUID matches one of the drives)

```shell
sudo tee -a '/etc/fstab' <<-'EOF' > /dev/null
# Our BTRFS data drive.
UUID="79319f1f-389d-4f1a-9c19-1ba384bfdda7"   /data   btrfs   defaults,compress,autodefrag,noatime,nodiratime   0 0
EOF
```

Maintenance scripts:

```shell
sudo mkdir -p /usr/share/btrfsmaintenance && \
sudo git clone https://github.com/kdave/btrfsmaintenance.git /usr/share/btrfsmaintenance
```

Update `/usr/share/btrfsmaintenance/sysconfig.btrfsmaintenance`, particularly the mount points to maintain.

Then run:

```shell
sudo /usr/share/btrfsmaintenance/./btrfsmaintenance-refresh-cron.sh
```

## General Configuration

Manually bond the physical network interfaces, then create a bridge off the bond. Perhaps do this through [Cockpit](https://192.168.86.250:9090/network).

Run the repo's setup script:

```shell
/opt/bb-file-server/./setup.sh
```

# Portainer

[Portainer Deployment Docs](https://portainer.readthedocs.io/en/stable/deployment.html)

Mount `/var/run/docker.sock` to gain host control over docker.
To function with host's SELinux active, use `--privileged`.
Persist configuration by mounting container's `/data`.

[Access](http://192.168.86.250:9000)

# Docker Images

## MariaDB

A drop in replacement for MySQL that is used by other docker images.


Create a user for our dockers to use:
```shell
echo "MySQL (MariaDB) password for user '${USER}':"
cat /opt/bb-file-server/.secrets/mysql_root_pass.txt

# Create a user.
tee /tmp/script.sql <<-"EOC"
CREATE USER '${USER}'@'localhost' IDENTIFIED BY '$(cat /opt/bb-file-server/.secrets/mysql_root_pass.txt)';
GRANT ALL PRIVILEGES ON *.* TO '${USER}'@'localhost';
FLUSH PRIVILEGES;
EOC

sudo docker cp /tmp/script.sql mysql:/script.sql

sudo docker exec -ti mysql /bin/sh -c "mysql --user=root --password='$(cat /opt/bb-file-server/.secrets/mysql_root_pass.txt)' < /script.sql"
```

## OpenVPN Server

```shell
# Change admin password.
docker exec -it openvpn passwd admin
# Add user to connect as.
docker exec -it openvpn adduser ${USER}


# Allow remote connections to our VPN.
sudo firewall-cmd --zone=FedoraServer --permanent --add-rich-rule 'rule family=ipv4 port port=1194 protocol=udp accept'
sudo firewall-cmd --zone=FedoraServer --permanent --add-rich-rule 'rule family=ipv4 port port=9443 protocol=tcp accept'
sudo firewall-cmd --reload
```

Then:
* Login as an admin on the [server admin page](https://192.168.86.250:943/admin/).
* Go to Server Network Settings.
* Change "Hostname or IP Address:" to the name or IP we will use to access the server from remote.
  - e.g. myname.duckdns.org
* Click the "Save Settings" button at the bottom.
* Click the "Update Server" button at the top.
* Go to "VPN Settings".
* Ensure the home network is added to the "Specify the private subnets to which all clients should be given access (as 'network/netmask_bits', one per line)".
  - e.g. 192.168.86.0/24
* Ensure "Should client Internet traffic be routed through the VPN?" is set to "No".
* Click the "Save Settings" button at the bottom.
* Click the "Update Server" button at the top.
* Go to "User Permissions".
* Add the user added above (via "docker exec -it openvpn adduser ${USER}"), as "Admin" & "Allow Auto-login".
* Click the "Save Settings" button at the bottom.



## Fresh RSS

[Accessed here](http://192.168.86.250:8080)

```shell
tee /tmp/script.sql <<-'EOC'
CREATE DATABASE freshrss;
EOC

sudo docker cp /tmp/script.sql mariadb:/script.sql

sudo docker exec -ti mariadb /bin/sh -c "mysql --user=root --password='$(cat /opt/bb-file-server/.secrets/mysql_root_pass.txt)' < /script.sql"


In setup, configure the DB as:
Host - mariadb
User - bo
Password - $(cat /opt/bb-file-server/.secrets/mysql_root_pass.txt)
DB - freshrss


## Nginx + LetsEncrypt

```shell
tee /data/letsencrypt/nginx/site-confs/default <<-'EOC'
server {
  # listen 443 ssl http2 default_server;
  # listen [::]:443 ssl http2 default_server;
  listen *:443 ssl default_server;
  # listen [::]:443 ssl default_server;
  server_name _;
  # server_name_in_redirect off;
  keepalive_timeout 70;

  root /config/www;
  index index.html index.htm; # index.php;

  ssl on;
  ssl_certificate /config/keys/letsencrypt/fullchain.pem;
  ssl_certificate_key /config/keys/letsencrypt/privkey.pem;
  ssl_dhparam /config/nginx/dhparams.pem;
  ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';
  ssl_prefer_server_ciphers on;

  # Size limit of uploads. Default 1m
  client_max_body_size 0;

  #
  # server_tokens off;

  location @http-to-https {
    # We do not like to cache redirects.
    expires epoch;
    add_header "Cache-Control" "max-age=0, s-maxage=0, no-cache, no-store, must-revalidate, proxy-revalidate, post-check=0, pre-check=0";
    add_header "Pragma" "no-cache";
    add_header "Expires" "0";

    if ($request_method = POST) {
      # $request_uri = full original request URI (with arguments).
      return 307 https://$host$request_uri;
    }

    # $request_uri = full original request URI (with arguments).
    return 302 https://$host$request_uri;
  }

  error_page 301 303 = @no-perm-redirects;
  location @no-perm-redirects {
    # Save $upstream_http_location.
    set $saved_redirect_location '$upstream_http_location';

    # We do not like to cache redirects.
    expires epoch;
    add_header "Cache-Control" "max-age=0, s-maxage=0, no-cache, no-store, must-revalidate, proxy-revalidate, post-check=0, pre-check=0";
    add_header "Pragma" "no-cache";
    add_header "Expires" "0";

    if ($request_method = POST) {
      # $request_uri = full original request URI (with arguments).
      # return 307 http://localhost:80$request_uri;
      return 307 $saved_redirect_location;
    }

    # $request_uri = full original request URI (with arguments).
    # return 302 http://localhost:80$request_uri;
    return 302 $saved_redirect_location;
    # proxy_pass $saved_redirect_location;
  }

  # Always return "no content" for fav icon.
  location /favicon.ico {
    return 204;
  }

  location = /oauth2/auth {
    internal;
    proxy_pass http://oauth-firewall:4180;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URI $request_uri;

    # Use whatever hostname was used to access our nginx server.
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $host;

    # # To set the X-Forwarded-For to only contain the remote users IP:
    # proxy_set_header X-Forwarded-For $remote_addr;
    # To append the remote users IP to any existing X-Forwarded-For value:
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    #
    proxy_set_header X-Real-IP $remote_addr;
    # Proxy http or https depending on what is used to access our nginx server.
    proxy_set_header X-Scheme 'http';
    # proxy_set_header X-Scheme $scheme;
    proxy_set_header X-Forwarded-Proto $scheme;

    # http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_redirect
    # Sets the text that should be changed in the “Location” and “Refresh” header fields of a proxied server response.
    # Note: we want this due to form posts.
    proxy_redirect off;

    # http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_intercept_errors
    # Determines whether proxied responses with codes greater than or equal to 300 should be passed to a client or be
    # intercepted and redirected to nginx for processing with the error_page directive.
    proxy_intercept_errors on;
  }

  location = /oauth2/start {
    internal;
    proxy_pass http://oauth-firewall:4180;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URI $request_uri;

    # Use whatever hostname was used to access our nginx server.
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $host;

    # # To set the X-Forwarded-For to only contain the remote users IP:
    # proxy_set_header X-Forwarded-For $remote_addr;
    # To append the remote users IP to any existing X-Forwarded-For value:
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    #
    proxy_set_header X-Real-IP $remote_addr;
    # Proxy http or https depending on what is used to access our nginx server.
    proxy_set_header X-Scheme 'http';
    # proxy_set_header X-Scheme $scheme;
    proxy_set_header X-Forwarded-Proto $scheme;

    # http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_redirect
    # Sets the text that should be changed in the “Location” and “Refresh” header fields of a proxied server response.
    # Note: we want this due to form posts.
    proxy_redirect off;

    # http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_intercept_errors
    # Determines whether proxied responses with codes greater than or equal to 300 should be passed to a client or be
    # intercepted and redirected to nginx for processing with the error_page directive.
    proxy_intercept_errors on;
  }

  location = /oauth2/callback {
    auth_request off;
    proxy_pass http://oauth-firewall:4180;
    proxy_set_header X-Original-URI $request_uri;

    # Use whatever hostname was used to access our nginx server.
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $host;

    # # To set the X-Forwarded-For to only contain the remote users IP:
    # proxy_set_header X-Forwarded-For $remote_addr;
    # To append the remote users IP to any existing X-Forwarded-For value:
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    #
    proxy_set_header X-Real-IP $remote_addr;
    # Proxy http or https depending on what is used to access our nginx server.
    proxy_set_header X-Scheme 'http';
    # proxy_set_header X-Scheme $scheme;
    proxy_set_header X-Forwarded-Proto $scheme;

    # http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_redirect
    # Sets the text that should be changed in the “Location” and “Refresh” header fields of a proxied server response.
    # Note: we want this due to form posts.
    proxy_redirect off;

    # http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_intercept_errors
    # Determines whether proxied responses with codes greater than or equal to 300 should be passed to a client or be
    # intercepted and redirected to nginx for processing with the error_page directive.
    proxy_intercept_errors on;
  }

  location / {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$request_uri;

    # Redirect if not using HTTPS.
    if ($http_x_forwarded_proto = "http") {
      error_page 418 = @http-to-https;
      return 418;
    }

    # Our target backend server to proxy.
    proxy_pass http://freshrss;

    # Use whatever hostname was used to access our nginx server.
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $host;

    # # To set the X-Forwarded-For to only contain the remote users IP:
    # proxy_set_header X-Forwarded-For $remote_addr;
    # To append the remote users IP to any existing X-Forwarded-For value:
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    #
    proxy_set_header X-Real-IP $remote_addr;
    # Proxy http or https depending on what is used to access our nginx server.
    proxy_set_header X-Scheme 'http';
    # proxy_set_header X-Scheme $scheme;
    proxy_set_header X-Forwarded-Proto $scheme;

    # http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_redirect
    # Sets the text that should be changed in the “Location” and “Refresh” header fields of a proxied server response.
    # Note: we want this due to form posts.
    proxy_redirect off;
  }
}
EOC

sudo docker restart letsencrypt


# Allow HTTPS through the firewall.
sudo firewall-cmd --zone=FedoraServer --permanent --add-rich-rule 'rule family=ipv4 port port=443 protocol=tcp accept'
sudo firewall-cmd --reload
```

## OAuth2 Proxy (OAuth Firewall)

# Virtualization

References:
* https://jamielinux.com/docs/libvirt-networking-handbook/bridged-network.html
* ...

```shell
sudo dnf install -y iso-codes edk2-ovmf bridge-utils


sudo tee /etc/sysctl.d/bridge.conf <<-'EOC'
net.bridge.bridge-nf-call-ip6tables=0
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-arptables=0
EOC


# Apply the above conf whenever a bridge is loaded.
sudo tee /etc/udev/rules.d/99-bridge.rules <<-'EOC'
ACTION=="add", SUBSYSTEM=="module", KERNEL=="br_netfilter", RUN+="/sbin/sysctl -p /etc/sysctl.d/bridge.conf"
EOC


echo "NM_BOND_BRIDGE_VLAN_ENABLED=yes" >> /etc/sysconfig/network
service NetworkManager restart
```
