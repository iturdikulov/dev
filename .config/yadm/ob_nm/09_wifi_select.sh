#!/usr/bin/env bash
# 09_wifi_select.sh - pick a Wi-Fi network as the primary WAN and prioritise it.
# Interactive: lists nearby/known networks on wlp6s0, connects, and sets a high
# autoconnect-priority so NetworkManager prefers Wi-Fi over the wired backup and
# fails over automatically when Wi-Fi is unavailable.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

sudo nmcli radio wifi on || true

log_info "Scanning for networks on $WAN_WIFI..."
sudo nmcli device wifi rescan ifname "$WAN_WIFI" >/dev/null 2>&1 || true
sleep 2
nmcli --fields IN-USE,SSID,SIGNAL,SECURITY device wifi list ifname "$WAN_WIFI" || true

echo
read -r -p "SSID to use as primary WAN (blank to skip): " ssid
if [[ -z "$ssid" ]]; then
    log_warn "No SSID entered; leaving Wi-Fi unchanged."
    exit 0
fi

name="wan-wifi-$ssid"

if nm_con_exists "$name"; then
    log_info "Reusing existing profile '$name'"
    sudo nmcli connection up "$name" || log_warn "Could not activate '$name'"
else
    read -r -s -p "Password (blank for open/known network): " psk
    echo
    if [[ -n "$psk" ]]; then
        sudo nmcli device wifi connect "$ssid" password "$psk" \
            ifname "$WAN_WIFI" name "$name"
    else
        sudo nmcli device wifi connect "$ssid" \
            ifname "$WAN_WIFI" name "$name"
    fi
fi

log_info "Setting '$name' as the preferred WAN (priority $WIFI_PRIORITY, route-metric $WIFI_ROUTE_METRIC)"
sudo nmcli connection modify "$name" \
    connection.autoconnect yes \
    connection.autoconnect-priority "$WIFI_PRIORITY" \
    ipv4.route-metric "$WIFI_ROUTE_METRIC"

# Re-apply connection so route-metric takes effect.
sudo nmcli connection up "$name" ifname "$WAN_WIFI" || log_warn "Could not reactivate '$name'"

log_info "Wi-Fi '$ssid' is now primary WAN; $WAN_WIRED remains the backup."
