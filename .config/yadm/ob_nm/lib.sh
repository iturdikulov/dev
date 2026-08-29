#!/usr/bin/env bash
# lib.sh - shared setup for ob_nm router runners.
# Sourced by every 0x_*.sh stage; provides logging/helpers from the repo's
# runs/utils.sh plus router-specific defaults (overridable via ob_nm.conf).

set -euo pipefail

OB_NM_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_DIR="$(cd -- "$OB_NM_DIR/.." >/dev/null 2>&1 && pwd)"

# Router provisioning does not want the language-toolchain auto-installer that
# utils.sh runs for interactive desktop runners.
export YADM_SKIP_TOOLCHAINS=1

# shellcheck source=../runs/utils.sh
source "$REPO_DIR/runs/utils.sh"

# --- Router defaults (override in ob_nm.conf) --------------------------------
WAN_WIFI="wlp6s0"                 # primary WAN (managed by NetworkManager)
WAN_WIRED="enp2s0"                # backup WAN (DHCP client)
LAN_IFACES="enp3s0 enp4s0 enp5s0" # ports bridged into the LAN
LAN_BRIDGE="br-lan"
LAN_ADDR="192.168.1.1"
LAN_CIDR="24"
DHCP_START="192.168.1.100"
DHCP_END="192.168.1.200"
DHCP_LEASE="12h"
WIFI_PRIORITY="100" # autoconnect-priority for the Wi-Fi WAN
WIRED_PRIORITY="10" # autoconnect-priority for the wired backup WAN
WIFI_ROUTE_METRIC="50"   # lower = preferred default route when Wi-Fi is up
WIRED_ROUTE_METRIC="200" # higher = backup when both WANs are connected

MIHOMO_REPO="MetaCubeX/mihomo"
MIHOMO_BIN="/usr/local/bin/mihomo"
MIHOMO_DIR="/etc/mihomo"
MIHOMO_MIXED_PORT="7890"
MIHOMO_DNS_PORT="7874"
MIHOMO_CONTROLLER_PORT="9090"

SYSTEM_DIR="$OB_NM_DIR/system"

if [[ -f "$OB_NM_DIR/ob_nm.conf" ]]; then
    # shellcheck source=/dev/null
    source "$OB_NM_DIR/ob_nm.conf"
fi

# Non-interactive sudo when pass.test exists (local only; do not commit secrets).
if [[ -f "$OB_NM_DIR/pass.test" ]]; then
    unalias sudo 2>/dev/null || true
    _OB_NM_SUDO_PASS="$(<"$OB_NM_DIR/pass.test")"
    sudo() {
        unset SUDO_ASKPASS
        echo "$_OB_NM_SUDO_PASS" | /usr/bin/sudo -S -- "$@"
    }
fi

# Hard-link a single file from ob_nm/system into / (matches the repo pattern in
# runs/singbox and utils.sh:symlink_sys_tree_into_root). Idempotent: an existing
# regular (non-symlink) file at the destination is left untouched.
link_system_file() {
    local rel="${1#/}"
    local force="${2:-0}"
    local src="$SYSTEM_DIR/$rel"
    local dest="/$rel"

    if [[ ! -f "$src" ]]; then
        log_error "Missing system file: $src"
        return 1
    fi

    sudo mkdir -p "$(dirname "$dest")"

    if [[ "$force" != "1" && -e "$dest" && ! -L "$dest" ]]; then
        log_info "Already present, leaving as-is: $dest"
        return 0
    fi
    if [[ -L "$dest" ]]; then
        sudo rm -f "$dest"
    elif [[ "$force" == "1" && -e "$dest" ]]; then
        sudo rm -f "$dest"
    fi

    log_info "Linking $dest -> $src"
    sudo ln "$src" "$dest"
}

# True when an NetworkManager connection profile with the given name exists.
nm_con_exists() {
    nmcli -t -f NAME con show 2>/dev/null | grep -qx -- "$1"
}
