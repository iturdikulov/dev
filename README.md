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

## Goal

20 minute script using bash

No more ansible, simple bashing and I like what i have created
