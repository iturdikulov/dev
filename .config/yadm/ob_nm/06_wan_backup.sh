#!/usr/bin/env bash
# 06_wan_backup.sh - configure the wired WAN (enp2s0) as a DHCP backup uplink.
# Disruptive: this touches the interface that is likely your current uplink, so
# run it from a local console/KVM, not over an SSH session on enp2s0.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

name="wan-$WAN_WIRED"

if nm_con_exists "$name"; then
    log_info "Updating existing WAN profile '$name'"
    sudo nmcli connection modify "$name" \
        ipv4.method auto ipv6.method auto \
        connection.autoconnect yes \
        connection.autoconnect-priority "$WIRED_PRIORITY" \
        ipv4.route-metric "$WIRED_ROUTE_METRIC"
else
    log_info "Creating wired WAN backup '$name' on $WAN_WIRED (priority $WIRED_PRIORITY)"
    sudo nmcli connection add type ethernet \
        con-name "$name" ifname "$WAN_WIRED" \
        ipv4.method auto ipv6.method auto \
        connection.autoconnect yes \
        connection.autoconnect-priority "$WIRED_PRIORITY" \
        ipv4.route-metric "$WIRED_ROUTE_METRIC"
fi

sudo nmcli connection up "$name" || log_warn "Could not activate $name (cable unplugged?)"

log_info "Wired backup WAN ready on $WAN_WIRED (autoconnect-priority $WIRED_PRIORITY)."
