#!/usr/bin/env bash
# 03_mihomo_update.sh - keep Mihomo up to date and self-register in cron.
#
# Standalone on purpose: it must run non-interactively from root's crontab, so
# it does NOT source lib.sh/utils.sh (those assume an interactive non-root user).
# It updates the binary only when the latest release differs from the installed
# version, restarts the service only if it is currently running, and registers
# itself in the root crontab on first run.

set -euo pipefail

MIHOMO_REPO="MetaCubeX/mihomo"
MIHOMO_BIN="/usr/local/bin/mihomo"
CRON_SCHEDULE="0 4 * * *"

SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/$(basename -- "${BASH_SOURCE[0]}")"

SUDO=""
if [[ $(id -u) -ne 0 ]]; then
    SUDO="sudo"
fi

log() { printf '[mihomo-update] %s\n' "$*"; }

# Ensure an idempotent entry in root's crontab pointing at this script.
register_cron() {
    local current entry="$CRON_SCHEDULE $SELF"
    current="$($SUDO crontab -l 2>/dev/null || true)"

    if printf '%s\n' "$current" | grep -qF -- "$SELF"; then
        log "cron entry already present"
        return 0
    fi

    log "registering cron entry: $entry"
    printf '%s\n%s\n' "$current" "$entry" | sed '/^$/d' | $SUDO crontab -
}

# Resolve the newest release tag from the GitHub "latest" redirect.
latest_tag() {
    curl -fsSIL "https://github.com/${MIHOMO_REPO}/releases/latest" |
        sed -n 's/^[Ll]ocation: .*\/releases\/tag\/\([^[:space:]\r]*\).*/\1/p' |
        tail -n 1
}

installed_version() {
    if [[ -x "$MIHOMO_BIN" ]]; then
        "$MIHOMO_BIN" -v 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1
    fi
}

arch_suffix() {
    case "$(dpkg --print-architecture)" in
        amd64) echo "amd64" ;;
        arm64) echo "arm64" ;;
        armhf) echo "armv7" ;;
        *)
            log "unsupported architecture: $(dpkg --print-architecture)"
            exit 1
            ;;
    esac
}

main() {
    register_cron

    local tag current
    tag="$(latest_tag)"
    if [[ -z "$tag" ]]; then
        log "could not resolve latest release tag"
        exit 1
    fi

    current="$(installed_version || true)"
    log "installed=${current:-none} latest=${tag}"

    if [[ "$current" == "$tag" ]]; then
        log "already up to date"
        exit 0
    fi

    local march asset url tmp_gz tmp_bin
    march="$(arch_suffix)"
    asset="mihomo-linux-${march}-${tag}.gz"
    url="https://github.com/${MIHOMO_REPO}/releases/download/${tag}/${asset}"

    tmp_gz="$(mktemp)"
    tmp_bin="$(mktemp)"
    trap 'rm -f "$tmp_gz" "$tmp_bin"' EXIT

    log "downloading $url"
    curl -fsSL -o "$tmp_gz" "$url"
    gunzip -c "$tmp_gz" >"$tmp_bin"
    $SUDO install -m 0755 "$tmp_bin" "$MIHOMO_BIN"
    log "updated Mihomo to ${tag}"

    if $SUDO systemctl is-active --quiet mihomo; then
        log "service is running; restarting"
        $SUDO systemctl restart mihomo
    else
        log "service not running; leaving it stopped"
    fi
}

main "$@"
