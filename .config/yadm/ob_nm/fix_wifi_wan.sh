#!/usr/bin/env bash
# fix_wifi_wan.sh - tune Wi-Fi WAN routing without switching uplink (safe over SSH).
#
# Usage:
#   ./fix_wifi_wan.sh              # fix all known Wi-Fi WAN profiles (no connect)
#   ./fix_wifi_wan.sh switch NAME  # activate Wi-Fi WAN — LOCAL CONSOLE ONLY
#
# Why: lower ipv4.route-metric on Wi-Fi makes it the default route when both WANs
# are up. Wired backup keeps a higher metric (200 vs 50).

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

configure_wifi_profile() {
    local name="$1"
    log_info "Profile '$name': route-metric $WIFI_ROUTE_METRIC, autoconnect-priority $WIFI_PRIORITY"
    sudo nmcli connection modify "$name" \
        connection.autoconnect yes \
        connection.autoconnect-priority "$WIFI_PRIORITY" \
        ipv4.route-metric "$WIFI_ROUTE_METRIC" \
        connection.interface-name "$WAN_WIFI"
}

fix_profiles() {
    sudo nmcli radio wifi on || true
    sudo nmcli device set "$WAN_WIFI" managed yes 2>/dev/null || true

    if nm_con_exists "wan-$WAN_WIRED"; then
        log_info "Wired backup 'wan-$WAN_WIRED': route-metric $WIRED_ROUTE_METRIC"
        sudo nmcli connection modify "wan-$WAN_WIRED" \
            ipv4.route-metric "$WIRED_ROUTE_METRIC" \
            connection.autoconnect-priority "$WIRED_PRIORITY"
    fi

    local found=0
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        configure_wifi_profile "$name"
        found=1
    done < <(nmcli -t -f NAME,TYPE con show 2>/dev/null | awk -F: '$2=="802-11-wireless" {print $1}')

    if (( found == 0 )); then
        log_warn "No Wi-Fi profiles found."
    fi

    log_info "Profiles updated. Active routes change only after reconnect."
    log_info "To use Wi-Fi WAN, run from local console (not SSH over wired):"
    log_info "  $0 switch Rostelecom_UUS"
}

switch_wifi() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "Usage: $0 switch CONNECTION_NAME"
        exit 1
    fi
    if ! nm_con_exists "$name"; then
        log_error "Unknown connection: $name"
        exit 1
    fi

    configure_wifi_profile "$name"
    log_warn "Switching default route to Wi-Fi — run this from KVM/console if SSH may drop."
    sudo nmcli connection up "$name" ifname "$WAN_WIFI"
    ip route show default
    log_info "Test: curl -s --max-time 5 ifconfig.me"
}

case "${1:-fix}" in
    fix|fix-profiles) fix_profiles ;;
    switch) shift; switch_wifi "${1:-}" ;;
    *)
        echo "Usage: $0 [fix|switch CONNECTION]" >&2
        exit 1
        ;;
esac
