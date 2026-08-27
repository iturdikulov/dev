#!/bin/bash
# Manage a LUKS file vault in the current working directory (by default).
#   luks-vault.sh          — interactive menu
#   luks-vault.sh open     — open, mount, enter shell in vault
#   luks-vault.sh create   — create vault.img, then enter shell
#   luks-vault.sh close    — umount & close

set -euo pipefail

VAULT_IMG="${PWD}/vault.img"
MAPPER_NAME="vault"
MAPPER_DEV="/dev/mapper/${MAPPER_NAME}"
MOUNT_POINT="/tmp/vault-${USER}"
# cryptsetup lives in sbin; user PATH often omits it
PATH="/usr/sbin:/sbin:${PATH}"
CRYPTSETUP=""

usage() {
    echo "Usage: $0 [open|create|close]" >&2
    exit 1
}

die() {
    echo "error: $*" >&2
    exit 1
}

resolve_cryptsetup() {
    local p
    for p in "$(command -v cryptsetup 2>/dev/null || true)" /usr/sbin/cryptsetup /sbin/cryptsetup; do
        [[ -n "$p" && -x "$p" ]] || continue
        CRYPTSETUP="$p"
        return 0
    done
    return 1
}

ensure_cryptsetup() {
    if resolve_cryptsetup; then
        return 0
    fi
    echo "cryptsetup not found; installing via apt..."
    sudo apt-get install -y cryptsetup
    resolve_cryptsetup || die "cryptsetup still missing after install"
}

is_mounted() {
    findmnt -n -T "$MOUNT_POINT" >/dev/null 2>&1 || return 1
    findmnt -n -S "$MAPPER_DEV" "$MOUNT_POINT" >/dev/null 2>&1
}

ensure_mountpoint() {
    if [[ ! -d "$MOUNT_POINT" ]]; then
        mkdir -m 700 "$MOUNT_POINT"
    fi
    chmod 700 "$MOUNT_POINT" 2>/dev/null || true
}

mount_vault() {
    ensure_mountpoint
    sudo mount "$MAPPER_DEV" "$MOUNT_POINT"
    sudo chown "${USER}:" "$MOUNT_POINT"
    echo "Mounted at ${MOUNT_POINT}"
}

enter_vault() {
    cd "$MOUNT_POINT" || die "cannot cd to ${MOUNT_POINT}"
    echo "Entering ${MOUNT_POINT} (exit to leave)"
    exec "${SHELL:-/bin/bash}" -i
}

cmd_open() {
    local dir
    read -r -p "Directory [${PWD}]: " dir
    dir="${dir:-$PWD}"
    dir="$(realpath -m "$dir")"
    VAULT_IMG="${dir}/vault.img"
    [[ -f "$VAULT_IMG" ]] || die "no vault at ${VAULT_IMG}; run: $0 create"

    if is_mounted; then
        echo "Already mounted at ${MOUNT_POINT}"
        enter_vault
    fi

    if [[ ! -e "$MAPPER_DEV" ]]; then
        sudo "$CRYPTSETUP" open "$VAULT_IMG" "$MAPPER_NAME"
    fi
    mount_vault
    enter_vault
}

cmd_close() {
    if findmnt -n "$MOUNT_POINT" >/dev/null 2>&1; then
        sudo umount "$MOUNT_POINT"
    fi
    if [[ -e "$MAPPER_DEV" ]]; then
        sudo "$CRYPTSETUP" close "$MAPPER_NAME"
    fi
    if [[ -d "$MOUNT_POINT" ]] && [[ -z "$(ls -A "$MOUNT_POINT" 2>/dev/null || true)" ]]; then
        rmdir "$MOUNT_POINT" 2>/dev/null || true
    fi
    echo "Closed"
}

cmd_create() {
    local dir size pass pass2
    read -r -p "Directory [${PWD}]: " dir
    dir="${dir:-$PWD}"
    dir="$(realpath -m "$dir")"
    [[ -d "$dir" ]] || die "not a directory: ${dir}"
    VAULT_IMG="${dir}/vault.img"
    [[ ! -e "$VAULT_IMG" ]] || die "vault already exists: ${VAULT_IMG}"

    read -r -p "Size [200M]: " size
    size="${size:-200M}"
    [[ "$size" =~ ^[0-9]+[KMGTP]?$ ]] || die "invalid size: ${size}"

    read -r -s -p "Password: " pass
    echo
    read -r -s -p "Confirm password: " pass2
    echo
    [[ "$pass" == "$pass2" ]] || die "passwords do not match"
    [[ -n "$pass" ]] || die "password is empty"

    truncate -s "$size" "$VAULT_IMG"
    printf '%s' "$pass" | sudo "$CRYPTSETUP" luksFormat --batch-mode --type luks2 \
        --cipher aes-xts-plain64 --key-size 512 \
        --integrity hmac-sha256 \
        --key-file=- "$VAULT_IMG"
    printf '%s' "$pass" | sudo "$CRYPTSETUP" open --key-file=- "$VAULT_IMG" "$MAPPER_NAME"
    sudo mkfs.ext4 -q "$MAPPER_DEV"
    mount_vault
    enter_vault
}

pick_action() {
    local choice
    echo "1) open" >&2
    echo "2) create" >&2
    echo "3) close" >&2
    read -r -p "Choice [1]: " choice
    case "${choice:-1}" in
        1|open)   echo open ;;
        2|create) echo create ;;
        3|close)  echo close ;;
        *) die "invalid choice: ${choice}" ;;
    esac
}

if [[ $# -eq 0 ]]; then
    ACTION="$(pick_action)"
else
    ACTION="$1"
fi

case "$ACTION" in
    -h|--help|help) usage ;;
esac

ensure_cryptsetup

case "$ACTION" in
    open)   cmd_open ;;
    create) cmd_create ;;
    close)  cmd_close ;;
    *) usage ;;
esac
