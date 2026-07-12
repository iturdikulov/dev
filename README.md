# Home of X device

Configuration and bootstrap specific device.

## Debian 13 installation

1. Download & Verify Netinst ISO - https://www.debian.org/CD/netinst/, use `debian-iso.sh` script.

2. Set root password during install, otherwise `sudo` will not work.

Partitioning:

- Entire disk
- EFI, bootable, name EFI
- root as btrfs, compress option, name root and label root
- swap name swap
- Scroll down to "Finish Partitioning" and "Write Changes"

Personal settings:

- username `inom`
- hostname based on russian rivers list

When you get to "software selection", deselect everything but System Utilities,
reboot, log into the shell with your username (`inom`) and password and
execute:

```
su -
apt update && apt upgrade

# a smaller, more flexible KDE environment compared to kde-full
apt install -y kde-standard

# check section below
apt purge ifupdown
```

## ifupdown issues

TODO: might be not actual!

You will need to remove the ifupdown package, because that's what the installer
uses, while Gnome uses NetworkManager, so there will be a conflict and your WiFi
card won't show up (although you will actually be connected) until you do this
and reboot.

EDIT: you also need to edit the NetworkManager conf file:

```
su -
vi /etc/NetworkManager/NetworkManager.conf
# Charge managed=false to managed=true, save and reboot.
shutdown -r now
```

## Bootstrapping

Before running script, verify:

- sudo access
- added additional repositories in "Software & Update" or in /etc/sources.list (contrib, non-free, non-free-firmware). https://wiki.debian.org/SourcesList

```
su -
usermod -aG sudo <username>
```

I use yadm to bootstrap my system, there are some steps to make systemd work:

```
sudo apt install -y yadm git zsh
yadm clone https://github.com/iturdikulov/dev
```

## Post install

- System Prefrences: layout `gnome-control-center keyboard`, keybindings Ctrl Position
- System Preferences: dark theme, default applications, resolution, scale-factor, refresh rate
- General behaviour: no animation?
- Sync Account in browser
- Export/Import gpg backup with script
- Sync files with sync.sh scrpt
- Execute runners
- Verify ~/.config/mimeapps.list
- Copy /etc configs, including specific ones (`update-grub`, `update-initramfs -u`, etc. if required)
