#!/usr/bin/env bash
# 05_lan_bridge.sh - bridge the LAN ports into br-lan with a static gateway IP.
# Disruptive: reconfigures the LAN interfaces via NetworkManager.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

if nm_con_exists "$LAN_BRIDGE"; then
    log_info "Bridge connection '$LAN_BRIDGE' already exists"
else
    log_info "Creating bridge '$LAN_BRIDGE' with ${LAN_ADDR}/${LAN_CIDR}"
    sudo nmcli connection add type bridge \
        con-name "$LAN_BRIDGE" ifname "$LAN_BRIDGE" \
        ipv4.method manual ipv4.addresses "${LAN_ADDR}/${LAN_CIDR}" \
        ipv6.method ignore \
        bridge.stp no \
        connection.autoconnect yes
fi

for iface in $LAN_IFACES; do
    slave="br-slave-$iface"
    if nm_con_exists "$slave"; then
        log_info "Bridge port '$slave' already exists"
    else
        log_info "Adding $iface to $LAN_BRIDGE"
        sudo nmcli connection add type ethernet \
            con-name "$slave" ifname "$iface" \
            master "$LAN_BRIDGE" \
            connection.autoconnect yes
    fi
done

log_info "Bringing up the bridge..."
sudo nmcli connection up "$LAN_BRIDGE" || log_warn "Could not activate $LAN_BRIDGE yet"
for iface in $LAN_IFACES; do
    sudo nmcli connection up "br-slave-$iface" || log_warn "Could not activate br-slave-$iface (cable unplugged?)"
done

log_info "LAN bridge ready at ${LAN_ADDR}/${LAN_CIDR}."
