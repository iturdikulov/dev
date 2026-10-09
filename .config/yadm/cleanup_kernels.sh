#!/usr/bin/env bash
# Purge old kernels: keeps the running kernel and the newest one from linux-image-amd64
# (the one grub boots by default), removes other linux-image/headers/kbuild packages.
# Safe to re-run; run it after rebooting into the new kernel.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=runs/utils.sh
source "$script_dir/runs/utils.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0")

  Purges kernel packages except the running kernel and the newest one
  installed by linux-image-amd64. Asks for confirmation.

EOF
}

while (($# > 0)); do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage >&2
            exit 2
            ;;
    esac
done

check_not_root

# Kernel "stem" shared by all packages of one kernel: 6.12.111+deb13 for
# linux-image-6.12.111+deb13-amd64, linux-headers-6.12.111+deb13-common, linux-kbuild-6.12.111+deb13
kernel_stem() {
    local version="$1"
    version="${version%-amd64}"
    echo "${version%-common}"
}

running_kernel="$(uname -r)"
if ! package_installed linux-image-amd64; then
    log_error "linux-image-amd64 is not installed, can't tell which kernel is the newest"
    exit 1
fi
newest_kernel="$(dpkg-query -W -f='${Depends}' linux-image-amd64 | sed -E 's/^linux-image-([^ ,]+).*/\1/')"

keep_stems=("$(kernel_stem "$running_kernel")" "$(kernel_stem "$newest_kernel")")
log_info "Keeping running kernel $running_kernel and newest kernel $newest_kernel"
if [[ "$running_kernel" != "$newest_kernel" ]]; then
    log_warn "Not running the newest kernel yet; reboot and re-run to remove $running_kernel too"
fi

# Versioned kernel packages only (stem starts with a digit) - metapackages like linux-image-amd64 stay
mapfile -t old_packages < <(
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'linux-image-*' 'linux-headers-*' 'linux-kbuild-*' 2>/dev/null |
        awk '$1 ~ /^[ih]i/ { print $2 }' |
        while read -r pkg; do
            stem="$(kernel_stem "${pkg#linux-*-}")"
            [[ "$stem" =~ ^[0-9] ]] || continue
            [[ " ${keep_stems[*]} " == *" $stem "* ]] && continue
            echo "$pkg"
        done |
        sort -u
)

if ((${#old_packages[@]} == 0)); then
    log_info "No old kernels to remove"
    exit 0
fi

log_info "Kernel packages to purge (${#old_packages[@]}):"
printf '  %s\n' "${old_packages[@]}"

read -rp "Purge these packages? [y/N] " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    log_warn "Aborted"
    exit 1
fi

# Holds from the old pinned kernel would block the purge
mapfile -t held < <(apt-mark showhold | grep -xF -f <(printf '%s\n' "${old_packages[@]}") || true)
if ((${#held[@]} > 0)); then
    sudo apt-mark unhold "${held[@]}"
fi

sudo apt-get purge -y "${old_packages[@]}"
sudo apt-get autoremove --purge -y

# DKMS-built modules (nvidia, xone, nct6687d) keep /lib/modules/<version> after the image is purged
for dir in /lib/modules/*; do
    version="$(basename "$dir")"
    if [[ "$version" != "$running_kernel" && "$version" != "$newest_kernel" ]] &&
        ! package_installed "linux-image-$version"; then
        log_info "Removing leftover $dir"
        sudo rm -rf -- "$dir"
    fi
done

log_info "Done. Remaining kernels:"
dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' 'linux-image-*' 2>/dev/null | awk '$1 == "ii" { print "  " $2, $3 }'
