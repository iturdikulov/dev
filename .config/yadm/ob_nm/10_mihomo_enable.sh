#!/usr/bin/env bash
# 10_mihomo_enable.sh - deploy config, fetch dashboard UI, enable mihomo.
# Safe over SSH: does not change default routes or WAN uplinks.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

log_info "Deploying Mihomo config and systemd unit"
link_system_file "etc/mihomo/config.yaml" 1
link_system_file "etc/systemd/system/mihomo.service"
link_system_file "etc/systemd/system/ob-nm-docker-route.service"
link_system_file "usr/local/sbin/ob-nm-docker-route.sh"
sudo mkdir -p /etc/systemd/system/mihomo.service.d
link_system_file "etc/systemd/system/mihomo.service.d/docker-route.conf"
sudo chmod 0755 /usr/local/sbin/ob-nm-docker-route.sh
sudo systemctl daemon-reload

log_info "Deploying zdash.lan nginx vhost"
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
link_system_file "etc/nginx/sites-available/zdash.lan" 1
sudo ln -sfn /etc/nginx/sites-available/zdash.lan /etc/nginx/sites-enabled/zdash.lan
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

log_info "Validating configuration"
sudo "$MIHOMO_BIN" -t -d "$MIHOMO_DIR"

log_info "Installing Metacubexd dashboard (if missing)"
ui_dir="$MIHOMO_DIR/ui/metacubexd"
if [[ ! -f "$ui_dir/index.html" ]]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    download_file \
        "https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip" \
        "$tmp/ui.zip"
    sudo mkdir -p "$MIHOMO_DIR/ui"
    unzip -qo "$tmp/ui.zip" -d "$tmp"
    sudo rm -rf "$ui_dir"
    sudo mv "$tmp/metacubexd-gh-pages" "$ui_dir"
fi

log_info "Enabling and starting mihomo"
sudo systemctl enable --now mihomo ob-nm-docker-route.service

sleep 2
if ! sudo systemctl is-active --quiet mihomo; then
    log_error "mihomo failed to start; see: journalctl -u mihomo -n 50 --no-pager"
    exit 1
fi

log_info "Mihomo is active."
log_info "  Proxy (LAN):  ${LAN_ADDR}:7890  (HTTP/SOCKS mixed)"
log_info "  DNS (LAN):    ${LAN_ADDR}:7874"
log_info "  Web UI:       http://${LAN_ADDR}:9090/ui/metacubexd/"
log_info "  Dashboard:    http://zdash.lan/"
log_info "  API secret:   see secret: in $MIHOMO_DIR/config.yaml"
