#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=runs/utils.sh
source "$script_dir/runs/utils.sh"

SYNC_DIRS_DEFAULT=(
    az
    Desktop/web
    Music
    Templates
    .password-store
    .config/microsoft-edge
)

sync_dir_excludes() {
    case "$1" in
        az) printf '%s\n' runtime/ ;;
    esac
}

yadm_sync_home() {
    local base_path="${1:-}"
    local output_dir="${SYNC_DEST:-$HOME}"
    local dir sync_args exclude

    if [[ -z "$base_path" ]]; then
        read -rp "Source base path for sync, e.g. user@host:/home/user (empty to skip): " base_path
    fi

    [[ -n "$base_path" ]] || return 0

    read -rp "Sync .ssh plus dirs (${SYNC_DIRS_DEFAULT[*]}) into '$output_dir'? (y/n) "
    [[ "$REPLY" =~ ^[Yy]$ ]] || return 0

    rcp --exclude .ssh/known_hosts "$base_path/.ssh" "$output_dir"
    for dir in "${SYNC_DIRS_DEFAULT[@]}"; do
        sync_args=()
        while IFS= read -r exclude; do
            [[ -n "$exclude" ]] || continue
            sync_args+=(--exclude "$exclude")
        done < <(sync_dir_excludes "$dir")
        rcp "${sync_args[@]}" "$base_path/$dir" "$output_dir/"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    yadm_sync_home "${BASE_PATH:-}"
fi
