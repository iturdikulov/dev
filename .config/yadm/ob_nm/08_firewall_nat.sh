#!/usr/bin/env bash
# 08_firewall_nat.sh - load the nftables NAT + firewall ruleset.
# Disruptive: enables the firewall. WAN-side inbound (e.g. SSH over enp2s0) is
# dropped after this runs; manage the router from the LAN side.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

# Always install our ruleset: a distro-default /etc/nftables.conf leaves LAN
# clients without NAT. Use a hard link (not a symlink into $HOME) so nftables
# can load it at boot.
link_system_file "etc/nftables.conf" 1

log_info "Validating ruleset..."
sudo nft -c -f /etc/nftables.conf

log_info "Enabling and (re)loading nftables..."
sudo systemctl enable nftables
sudo systemctl restart nftables

if systemctl is-active --quiet docker 2>/dev/null; then
    log_info "Restarting docker so its firewall hooks are re-registered..."
    sudo systemctl restart docker
fi

link_system_file "usr/local/sbin/ob-nm-docker-route.sh"
sudo chmod 0755 /usr/local/sbin/ob-nm-docker-route.sh
link_system_file "etc/systemd/system/ob-nm-docker-route.service"
sudo systemctl daemon-reload
sudo systemctl enable ob-nm-docker-route.service
sudo systemctl restart ob-nm-docker-route.service

log_info "Firewall active; NAT masquerade enabled on the WAN interfaces."
