#!/usr/bin/env bash

set -euo pipefail

# utils.sh - Common utility functions for idempotent runners

# Color definitions for status messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Check if we're running as root
check_not_root() {
    if [[ $(id -u) -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
}

# Check if HOME is set
check_home_set() {
    if [[ -z "$HOME" ]]; then
        log_error "HOME environment variable is not set"
        exit 1
    fi
}

# Check if a command exists
command_exists() { command -v "$1" >/dev/null 2>&1; }

# An rsync wrapper for gitignore-oriented syncs.
rcp() {
    #   -a = -rlptgoD
    #   -r = recursive
    #   -l = copy symlinks as symlinks
    #   -p = preserve permissions
    #   -t = preserve mtimes
    #   -g = preserve owning group
    #   -o = preserve owner
    # -z = use compression
    # -P = show progress on transferred file
    # -J = don't touch mtimes on symlinks (always errors)
    rsync -rtzPJ \
        --include=.git/ \
        "$@"
}

# Change directory or exit 1 after logging the failure.
cd_or_exit() {
    local dir=$1
    if ! cd -- "$dir"; then
        log_error "Failed to change directory to: $dir"
        exit 1
    fi
}

# Check if a package is installed (Debian/Ubuntu)
package_installed() { dpkg -l "$1" | grep -q '^ii' >/dev/null 2>&1; }

# True if apt package lists should be refreshed (missing cache or older than ~7 days).
apt_cache_is_stale() {
    local cache=/var/cache/apt/pkgcache.bin
    local week_sec=$((7 * 24 * 60 * 60))
    local now mtime age

    if [[ ! -f "$cache" ]]; then
        return 0
    fi

    now=$(date +%s)
    mtime=$(stat -c %Y -- "$cache" 2>/dev/null) || return 0
    age=$((now - mtime))
    ((age > week_sec))
}

# Install package if not already installed
install_packages() {
    local pkg_names=("$@")

    if apt_cache_is_stale; then
        log_info "Package index is missing or older than 7 days; running apt update..."
        sudo apt-get update
    fi

    for pkg_name in "${pkg_names[@]}"; do
        if ! package_installed "$pkg_name"; then
            log_info "Installing $pkg_name..."
            sudo apt install -y "$pkg_name"
        else
            log_info "$pkg_name is already installed"
        fi
    done
}

# Remove package if installed
remove_packages() {
    local pkg_names=("$@")
    for pkg_name in "${pkg_names[@]}"; do
        if package_installed "$pkg_name"; then
            log_info "Removing $pkg_name..."
            sudo apt remove -y "$pkg_name"
        else
            log_info "$pkg_name is not installed"
        fi
    done
}

# Download file if it doesn't exist
download_file() {
    local url="$1"
    local output="$2"

    if [ -n "$output" ] && [ -f "$output" ]; then
        log_info "File already exists: $output"
        return 0
    fi

    log_info "Downloading $url..."

    if [ -n "$output" ]; then
        local wget_args=(--progress=bar --continue --output-document "$output")
    else
        local wget_args=(--progress=bar --continue)
    fi

    if command_exists wget2; then
        if ! wget2 "${wget_args[@]}" "$url"; then
            log_error "Failed to download file: $url"
            return 1
        fi
    elif command_exists wget; then
        if ! wget "${wget_args[@]}" "$url"; then
            log_error "Failed to download file: $url"
            return 1
        fi
    elif command_exists curl; then
        if [ -z "$output" ]; then
            log_error "curl download requires an output path"
            return 1
        fi
        if ! curl -fsSL -o "$output" "$url"; then
            log_error "Failed to download file: $url"
            return 1
        fi
    else
        log_error "Neither wget2, wget, nor curl found. Cannot download file."
        return 1
    fi

    return 0
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir"
        return 0
    fi
}

# Check if directory exists
directory_exists() {
    [ -d "$1" ]
}

# Check if file exists
file_exists() {
    [ -f "$1" ]
}

trash_path() {
    local path="$1"

    if [ ! -e "$path" ]; then
        log_warn "Path does not exist: $path"
        return 0
    fi

    if command_exists trash-put; then
        trash-put "$path"
    elif command_exists gio; then
        gio trash "$path"
    else
        rm -rf -- "$path"
    fi
}

# Create desktop entry if it doesn't exist
create_desktop_entry() {
    local filename="$1"
    local content="$2"
    local desktop_dir="$HOME/.local/share/applications"
    ensure_directory "$desktop_dir"

    log_info "Creating desktop entry: $desktop_dir/$filename"
    echo "$content" > "$desktop_dir/$filename.desktop"
    update-desktop-database $desktop_dir
}

# Find old versions of a software and suggest cleanup
find_old_versions() {
    local search_dir="$1"
    local pattern="$2"
    local current_version="$3"
    local cleanup_action="${4:-manual}"

    local old_versions
    old_versions=$(find "$search_dir" -maxdepth 1 -type d -name "$pattern" ! -name "$current_version" 2>/dev/null)

    if [ -z "$old_versions" ]; then
        return 0
    fi

    log_warn "Found old versions:"
    echo "$old_versions"

    if [ "$cleanup_action" != "trash" ]; then
        log_warn "Please remove old versions manually"
        return 0
    fi

    read -r -p "Move old versions to trash? [y/N] " remove_old_versions
    case "$remove_old_versions" in
    [Yy] | [Yy][Ee][Ss])
        while IFS= read -r old_version; do
            trash_path "$old_version"
        done <<< "$old_versions"
        ;;
    *)
        log_info "Keeping old versions"
        ;;
    esac
}

install_archive() {
    local app_name="$1"
    local url="$2"
    local version="$3"
    local install_dir="$4"
    local format="$5"

    local output_name="$app_name-$version.$format"
    local relative_install_dir="$install_dir"

    if [[ $install_dir != "$HOME/.local/bin" ]]; then
        if directory_exists "$install_dir"; then
            log_info "$app_name $version is already installed at $install_dir"
            return 1
        fi

        relative_install_dir="$HOME/.local"
    fi

    log_info "Installing $app_name $version..."

    # Change to temp directory
    cd /tmp || { log_error "Failed to change to /tmp directory"; exit 1; }

    download_file "$url" "$output_name"

    log_info "Extracting $app_name to $install_dir"

    if [[ "$output_name" == *.tar.gz ]] || [[ "$output_name" == *.tgz ]]; then
        tar -xzf "$output_name" -C "$relative_install_dir"
    elif [[ "$output_name" == *.tar.bz2 ]] || [[ "$output_name" == *.tbz2 ]]; then
        tar -xjf "$output_name" -C "$relative_install_dir"
    elif [[ "$output_name" == *.tar.xz ]] || [[ "$output_name" == *.txz ]]; then
        tar -xJf "$output_name" -C "$relative_install_dir"
    elif [[ "$output_name" == *.zip ]]; then
        unzip "$output_name" -d "$relative_install_dir"
    elif [[ "$output_name" == *.7z ]]; then
        7z x "$output_name" -o"$relative_install_dir" -y
    else
        log_error "Unsupported archive format: $output_name"
        rm -f "$output_name"
        return 1
    fi

    # Clean up download
    rm -f "$output_name"
    log_info "$app_name installation completed"

    return 0
}

# Toolchain packange managers
# Skip this block when a toolchain installer imports utils.sh; otherwise a
# missing command can make utils.sh call the same installer recursively.
CALLER_SCRIPT="$(basename -- "${BASH_SOURCE[1]:-}")"

if [[ ! " 04_go 05_python 06_rust 07_node " =~ " $CALLER_SCRIPT " ]]; then
    # 1. Get current script directory once
    DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

    # 2. Define tools: "command : installer_script : binary_paths_to_add"
    # Separate multiple paths for a single tool with a space
    tools=(
        "go:04_go:/usr/bin $HOME/go/bin"
        "uv:05_python:$HOME/.local/bin"
        "cargo:06_rust:$HOME/.cargo/bin"
        "npm:07_node:/usr/bin /usr/local/bin"
    )

    # 3. Process each toolchain in a single loop
    for entry in "${tools[@]}"; do
        # Split the string by the colon delimiter
        IFS=":" read -r cmd installer paths <<< "$entry"

        log_info "Ensuring toolchain: $cmd"

        # Install if missing
        if ! command -v "$cmd" &>/dev/null; then
            "$DIR/$installer"
        fi

        # Loop through and add any paths provided for the tool
        for bin_path in $paths; do
            if [ -d "$bin_path" ] && [[ ":$PATH:" != *":$bin_path:"* ]]; then
                export PATH="$PATH:$bin_path"
            fi
        done
    done
fi

# Check prerequisites
check_not_root
check_home_set
