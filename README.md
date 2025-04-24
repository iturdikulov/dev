## Minimal Debian 12 installation

Use the Netinst ISO - https://www.debian.org/CD/netinst/
Verify checksums.

Set root password during install, otherwise `sudo` will not work.

Partitioning:

- Entire disk
- EFI, bootable, name EFI
- root as btrfs, compress option, name root and label root
- swap name swap
- Scroll down to "Finish Partitioning" and "Write Changes"

When you get to "software selection", deselect everything
but System Utilities, reboot, log into the shell with your username and
password and:

```
su -
apt update && apt upgrade

# a smaller, more flexible KDE environment compared to kde-full
apt install -y kde-standard

apt purge ifupdown
```

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
- added additional repositories in "Software & Update" or in /etc/sources.list (contrib, non-free, non-free-firmware)
https://wiki.debian.org/SourcesList

On Debian you might need to add user into sudo group and reboot.

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

- System Prefrences: layout `kcmshell6 kcm_keyboard`, keybindings Ctrl Position
- System Preferences: dark theme, default applications
- Settings, `Dark` theme, Resolution, scale-factor, refresh rate
- Import shortcuts scheme: from `.config/yadm/shortcuts_scheme.kksrc`
- Sync Account
- Configure desktop app run arguments (in KDE very easy): foot --maximized
- Export/Import gpg backup with script
- Verify ~/.config/mimeapps.list
- https://wiki.calculate-linux.org/ru/btrbk, TODO: offline?
- https://wiki.debian.org/NvidiaGraphicsDrivers
- https://wiki.debian.org/NVIDIA%20Optimus
- https://gitlab.com/asus-linux/asusctl
- https://discussion.fedoraproject.org/t/kde-battery-charge-limit-reset-after-reboot/95628/8
- add kernel parameter to fix freeze `amd_pstate=active` (2025)
- https://wiki.archlinux.org/title/Laptop/ASUS

### LLM CLI

```
llm install llm-openrouter
pass show ...|y
llm keys set openrouter
llm models

# Set default model, for example
llm models default openrouter/google/gemini-2.5-flash-preview
```
