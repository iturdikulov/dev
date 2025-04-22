## Minimal Debian 12 installation

Set root password during install, otherwise `sudo` will not work.

Use the Netinst ISO, when you get to "software selection", deselect everything
but System Utilities, reboot, log into the shell with your username and
password and:

```
sudo apt update && sudo apt upgrade
sudo apt install gnome-core -y && sudo apt purge ifupdown -y && sudo shutdown -r now
```

That will get you a reboot to a barebones Gnome. You will need to remove the
ifupdown package, because that's what the installer uses, while Gnome uses
NetworkManager, so there will be a conflict and your WiFi card won't show up
(although you will actually be connected) until you do this and reboot. You can
take it further and just install gnome-session, but you will probably want to
install a file manager and terminal etc.

EDIT: you also need to edit the NetworkManager conf file:

```
sudo vi /etc/NetworkManager/NetworkManager.conf
# Charge managed=false to managed=true, save and reboot.
```

## Change fstab file to support compression

Currently, (04/2025), live installer does not support add mount option for btrfs compression.
So requires editing `fstab` file.

Before actual install (writing files), immediately after partitioning we can edit
the `fstab` file:

```
# Get to a terminal by doing ctrl+alt+f3
# Hit enter to activate the console
nano /target/mount/etc/fstab

# Adjust volume like this to enable compression
# add compress=lzo, compress=zlib, or compress=zstd
# I use level 1 for speed on nvme SDD

# Example, do NOT copy/paste, just use same mount option, "..." means there is
# some other mount options
... /  btrfs defaults,compress=zstd:1 ... 0 1
```

## Bootstrapping

Before running script, verify:
- sudo access
- added additional repositories in "Software & Update" or in /etc/sources.list (contrib, non-free, non-free-firmware)

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

- Hide unwanted titlebars of some apps: https://extensions.gnome.org/extension/723/pixel-saver/
- Focus new windows as I expected: https://extensions.gnome.org/extension/2182/noannoyance/
- System Prefrences: layout `kcmshell5 kcm_keyboard`
- System Preferences: dark theme, default applications
- Settings, `Dark` theme, Resolution, scale-factor, refresh rate
- Sync Account
- Configure desktop app run arguments (in KDE very easy): foot --maximized
- https://wiki.calculate-linux.org/ru/btrbk, TODO: offline?

### LLM CLI

```
llm install llm-openrouter
pass show ...|y
llm keys set openrouter
llm models

# Set default model, for example
llm models default openrouter/google/gemini-2.5-flash-preview
```
