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
