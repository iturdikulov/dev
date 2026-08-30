#!/usr/bin/env bash

# Shared NFS server setup and client-installer generation for yadm runners.

nfs_resolve_server_ip() {
    local server_ip_var="$1"
    local export_network="192.168.1.0/24"
    local server_ip="${!server_ip_var:-}"
    local -a detected_ips=()

    if [[ -n "$server_ip" ]]; then
        if [[ ! "$server_ip" =~ ^192\.168\.1\.[0-9]{1,3}$ ]]; then
            log_error "$server_ip_var must belong to $export_network"
            return 1
        fi
    else
        mapfile -t detected_ips < <(
            ip -o -4 addr show scope global |
                awk '$4 ~ /^192\.168\.1\./ { sub(/\/.*/, "", $4); print $4 }' |
                sort -u
        )
        if ((${#detected_ips[@]} != 1)); then
            log_error "Expected exactly one address in $export_network; set $server_ip_var explicitly"
            return 1
        fi
        server_ip="${detected_ips[0]}"
    fi

    printf '%s\n' "$server_ip"
}

nfs_write_exports() {
    local name="$1"
    local exports_file="$2"
    local access="$3"
    shift 3
    local source_dir exports_tmp export_options

    case "$access" in
        ro) export_options="ro,sync,root_squash,no_subtree_check" ;;
        rw) export_options="rw,sync,root_squash,no_subtree_check" ;;
        *)
            log_error "Unsupported NFS access mode: $access"
            return 1
            ;;
    esac

    exports_tmp="$(mktemp)"
    {
        printf '%s\n' "# Managed by ~/.config/yadm/runs/nfs_utils.sh ($name)"
        for source_dir in "$@"; do
            printf '%s\n' "$source_dir 192.168.1.0/24($export_options)"
        done
    } >"$exports_tmp"

    sudo install -d -m 0755 /etc/exports.d
    if sudo test -f "$exports_file" && ! sudo cmp -s "$exports_tmp" "$exports_file"; then
        sudo cp -a "$exports_file" "${exports_file}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    sudo install -m 0644 "$exports_tmp" "$exports_file"
    rm -f "$exports_tmp"
}

nfs_generate_client_installer() {
    local name="$1"
    local server_ip="$2"
    local access="$3"
    local client_script="$4"
    shift 4
    local source_uid source_gid fstab_options client_tmp client_output_tmp
    local -a exports=() mount_relative_paths=()
    local share source_dir mount_relative_path

    case "$access" in
        ro) fstab_options="ro,nofail,_netdev,nfsvers=4,x-systemd.automount,x-systemd.mount-timeout=30s,x-systemd.idle-timeout=60s" ;;
        rw) fstab_options="rw,nofail,_netdev,nfsvers=4,x-systemd.automount,x-systemd.mount-timeout=30s,x-systemd.idle-timeout=60s" ;;
        *)
            log_error "Unsupported NFS access mode: $access"
            return 1
            ;;
    esac

    for share in "$@"; do
        source_dir="${share%%:*}"
        mount_relative_path="${share#*:}"
        if [[ "$source_dir" == "$share" || -z "$mount_relative_path" ]]; then
            log_error "Invalid NFS share definition: $share"
            return 1
        fi
        exports+=("$source_dir")
        mount_relative_paths+=("$mount_relative_path")
    done

    source_uid="$(id -u)"
    source_gid="$(id -g)"
    client_tmp="$(mktemp)"
    {
        printf '%s\n\n' '#!/usr/bin/env bash' 'set -euo pipefail'
        printf 'NFS_SERVER=%q\n' "$server_ip"
        printf 'NFS_EXPORTS=(\n'
        printf '    %q\n' "${exports[@]}"
        printf ')\n'
        printf 'MOUNT_RELATIVE_PATHS=(\n'
        printf '    %q\n' "${mount_relative_paths[@]}"
        printf ')\n'
        printf 'NFS_UID=%q\nNFS_GID=%q\n' "$source_uid" "$source_gid"
        printf 'FSTAB_MARKER=%q\nFSTAB_OPTIONS=%q\n' "# yadm-nfs-$name" "$fstab_options"
        cat <<'EOF'

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

fstab_entry_state() {
    local source="$1" mountpoint="$2"

    sudo awk -v source="$source" -v mountpoint="$mountpoint" -v options="$FSTAB_OPTIONS" '
        $1 !~ /^#/ && $2 == mountpoint {
            if ($1 == source && $3 == "nfs" && $4 == options && $5 == "0" && $6 == "0") {
                found = "matching"
            } else {
                found = "conflict"
            }
        }
        END { print found == "" ? "missing" : found }
    ' /etc/fstab
}

[[ "$(id -u)" != "0" ]] || fail "Run this installer as the client user, not root."
[[ -n "${HOME:-}" && -d "$HOME" ]] || fail "The current user's home directory is unavailable."
[[ "$(id -u)" == "$NFS_UID" ]] || fail "The client user must have UID $NFS_UID for NFS permissions."
[[ "$(id -g)" == "$NFS_GID" ]] || fail "The client user must have GID $NFS_GID for NFS permissions."
command -v systemctl >/dev/null 2>&1 || fail "systemd is required to apply the bounded mount timeout."

if ! dpkg-query -W -f='${db:Status-Status}' nfs-common 2>/dev/null | grep -qx installed; then
    sudo apt-get update
    sudo apt-get install -y nfs-common
fi

missing_entries=0
for index in "${!NFS_EXPORTS[@]}"; do
    nfs_export="${NFS_EXPORTS[$index]}"
    mountpoint="$HOME/${MOUNT_RELATIVE_PATHS[$index]}"
    source="$NFS_SERVER:$nfs_export"
    fstab_state="$(fstab_entry_state "$source" "$mountpoint")"
    case "$fstab_state" in
        matching) printf 'Existing /etc/fstab entry is unchanged: %s\n' "$mountpoint" ;;
        missing) missing_entries=1 ;;
        conflict) fail "An existing /etc/fstab entry conflicts with $mountpoint; leaving /etc/fstab unchanged." ;;
    esac

    if mountpoint -q "$mountpoint"; then
        mounted_source="$(findmnt -n -o SOURCE --target "$mountpoint")"
        [[ "$mounted_source" == "$source" ]] || fail "$mountpoint is already mounted from $mounted_source."
        continue
    fi
    if [[ -e "$mountpoint" && ! -d "$mountpoint" ]]; then
        fail "$mountpoint exists but is not a directory."
    fi
    if [[ -d "$mountpoint" ]] && find "$mountpoint" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        fail "$mountpoint is not empty; refusing to hide its contents."
    fi
done

if ((missing_entries)); then
    backup="/etc/fstab.yadm-nfs-$(date +%Y%m%d%H%M%S).bak"
    additions="$(mktemp)"
    for index in "${!NFS_EXPORTS[@]}"; do
        nfs_export="${NFS_EXPORTS[$index]}"
        mountpoint="$HOME/${MOUNT_RELATIVE_PATHS[$index]}"
        source="$NFS_SERVER:$nfs_export"
        [[ "$(fstab_entry_state "$source" "$mountpoint")" == "missing" ]] || continue
        printf '%s\n' "$source $mountpoint nfs $FSTAB_OPTIONS 0 0 $FSTAB_MARKER" >>"$additions"
    done
    sudo cp -a /etc/fstab "$backup"
    sudo tee -a /etc/fstab <"$additions" >/dev/null
    rm -f "$additions"
    printf 'Added missing NFS entries to /etc/fstab (backup: %s)\n' "$backup"
fi

sudo systemctl daemon-reload
for index in "${!NFS_EXPORTS[@]}"; do
    nfs_export="${NFS_EXPORTS[$index]}"
    mountpoint="$HOME/${MOUNT_RELATIVE_PATHS[$index]}"
    source="$NFS_SERVER:$nfs_export"
    if ! mountpoint -q "$mountpoint"; then
        sudo install -d -o "$NFS_UID" -g "$NFS_GID" -m 0750 "$mountpoint"
        mount_unit="$(systemd-escape --path --suffix=mount "$mountpoint")"
        sudo systemctl start "$mount_unit"
    fi
    mounted_source="$(findmnt -n -o SOURCE --target "$mountpoint")"
    [[ "$mounted_source" == "$source" ]] || fail "$mountpoint did not mount from $source."
    printf 'Mounted NFS share at %s\n' "$mountpoint"
done
EOF
    } >"$client_tmp"

    client_output_tmp="$(mktemp "/tmp/nfs-${name}-client.XXXXXX")"
    install -m 0700 "$client_tmp" "$client_output_tmp"
    mv -f "$client_output_tmp" "$client_script"
    rm -f "$client_tmp"
}

nfs_setup_server() {
    local name="$1"
    local server_ip_var="$2"
    local exports_file="$3"
    local client_script="$4"
    local access="$5"
    shift 5
    local server_ip share source_dir
    local -a source_dirs=()

    check_not_root
    [[ -n "${HOME:-}" && -d "$HOME" ]] || {
        log_error "The current user's home directory is unavailable"
        return 1
    }
    for share in "$@"; do
        source_dir="${share%%:*}"
        [[ -d "$source_dir" ]] || {
            log_error "NFS source directory is missing: $source_dir"
            return 1
        }
        source_dirs+=("$source_dir")
    done

    server_ip="$(nfs_resolve_server_ip "$server_ip_var")"
    log_info "Configuring $access NFS exports to 192.168.1.0/24"
    install_packages nfs-kernel-server
    nfs_write_exports "$name" "$exports_file" "$access" "${source_dirs[@]}"
    sudo systemctl enable --now nfs-server
    sudo exportfs -ra
    sudo systemctl is-active --quiet nfs-server

    if command_exists ufw && sudo ufw status | grep -q '^Status: active$'; then
        sudo ufw allow nfs
    fi

    nfs_generate_client_installer "$name" "$server_ip" "$access" "$client_script" "$@"
}

nfs_log_client_instructions() {
    local name="$1"
    local client_script="$2"

    log_info "NFS $name export is active for a client user with UID $(id -u) and GID $(id -g)"
    log_info "Generated NFS client installer: $client_script"
    log_info "Copy it to the client: scp $client_script <client-host>:/tmp/"
    log_info "Run it on the client: ssh -t <client-host> 'bash /tmp/$(basename -- "$client_script")'"
}
