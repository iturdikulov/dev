#!/usr/bin/env bash
# 02_mihomo_install.sh - install the Mihomo binary + systemd unit.
# Internet-dependent stage. The service is registered but left stopped and
# disabled; wiring it into routing is a later, manual step.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

case "$(dpkg --print-architecture)" in
    amd64) march="amd64" ;;
    arm64) march="arm64" ;;
    armhf) march="armv7" ;;
    *)
        log_error "Unsupported architecture: $(dpkg --print-architecture)"
        exit 1
        ;;
esac

tag="$(github_latest_release_tag "$MIHOMO_REPO")"
log_info "Latest Mihomo release: $tag ($march)"

asset="mihomo-linux-${march}-${tag}.gz"
url="https://github.com/${MIHOMO_REPO}/releases/download/${tag}/${asset}"

tmp_gz="/tmp/${asset}"
rm -f "$tmp_gz"
download_file "$url" "$tmp_gz"

log_info "Installing binary to $MIHOMO_BIN"
tmp_bin="$(mktemp)"
gunzip -c "$tmp_gz" >"$tmp_bin"
sudo install -m 0755 "$tmp_bin" "$MIHOMO_BIN"
rm -f "$tmp_gz" "$tmp_bin"

log_info "Preparing $MIHOMO_DIR"
sudo mkdir -p "$MIHOMO_DIR"
link_system_file "etc/mihomo/config.yaml"

log_info "Registering systemd service"
link_system_file "etc/systemd/system/mihomo.service"
link_system_file "etc/systemd/system/ob-nm-docker-route.service"
link_system_file "usr/local/sbin/ob-nm-docker-route.sh"
sudo mkdir -p /etc/systemd/system/mihomo.service.d
link_system_file "etc/systemd/system/mihomo.service.d/docker-route.conf"
sudo chmod 0755 /usr/local/sbin/ob-nm-docker-route.sh
sudo systemctl daemon-reload

# Requirement: leave the service stopped (and disabled) after install.
sudo systemctl disable mihomo ob-nm-docker-route >/dev/null 2>&1 || true
sudo systemctl stop mihomo ob-nm-docker-route >/dev/null 2>&1 || true

log_info "Mihomo $tag installed. Service is registered but stopped/disabled."
log_info "Edit $MIHOMO_DIR/config.yaml, then: sudo systemctl enable --now mihomo"
