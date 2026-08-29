#!/usr/bin/env bash
# 07_dhcp_dns.sh - serve DHCP + DNS to LAN clients with dnsmasq.
# Disruptive: (re)starts dnsmasq.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

# dnsmasq binds only to br-lan, so it will not fight a stub resolver on
# 127.0.0.53. But if systemd-resolved grabbed the global :53 socket, free it so
# dnsmasq can bind reliably; NetworkManager keeps /etc/resolv.conf populated for
# the host, so host DNS keeps working.
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    log_warn "Disabling systemd-resolved so dnsmasq can own DNS on the LAN"
    sudo systemctl disable --now systemd-resolved
fi

# Debian default maps ob.lan to 127.0.1.1 — breaks LAN access by hostname.
if [[ -f /etc/hosts ]] && grep -qE '^127\.0\.1\.1[[:space:]]+ob(\.lan|\s|$)' /etc/hosts; then
    log_info "Fixing /etc/hosts: ob.lan → ${LAN_ADDR}"
    sudo sed -i -E "s/^127\.0\.1\.1([[:space:]]+ob(\.lan|\s|$))/${LAN_ADDR}\1/" /etc/hosts
fi

link_system_file "etc/dnsmasq.d/br-lan.conf" 1
link_system_file "etc/dnsmasq.d/ob-nm-hosts.conf" 1
link_system_file "etc/ob-nm-hosts.txt" 1

log_info "Enabling and (re)starting dnsmasq..."
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq

log_info "DHCP (${DHCP_START}-${DHCP_END}) and DNS are live on ${LAN_BRIDGE}."
