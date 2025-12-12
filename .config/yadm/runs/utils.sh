#!/usr/bin/env bash

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

# Check if a package is installed (Debian/Ubuntu)
package_installed() { dpkg -l "$1" | grep -q '^ii' >/dev/null 2>&1; }

# Install package if not already installed
install_packages() {
    local pkg_names=("$@")
    for pkg_name in "${pkg_names[@]}"; do
        if ! package_installed "$pkg_name"; then
            log_info "Installing $pkg_name..."
            sudo apt install -y "$pkg_name"
        else
            log_info "$pkg_name is already installed"
        fi
    done
}

# Download file if it doesn't exist
download_file() {
    local url="$1"
    local output="$2"

    if [ ! -f "$output" ]; then
        log_info "Downloading $url..."
        if command_exists wget2; then
            if ! wget2 --progress=bar --continue "$url" --output-document "$output"; then
                log_error "Failed to download file: $url"
                return 1
            fi
        else
            log_error "Neither wget2 nor wget found. Cannot download file."
            return 1
        fi
        return 0
    else
        log_info "File already exists: $output"
        return 1
    fi
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

# Create desktop entry if it doesn't exist
create_desktop_entry() {
    local filename="$1"
    local content="$2"
    local desktop_dir="$HOME/.local/share/applications"
    ensure_directory "$desktop_dir"

    log_info "Creating desktop entry: $desktop_dir/$filename"
    echo "$content" > "$desktop_dir/$filename.desktop"
}

# Find old versions of a software and suggest cleanup
find_old_versions() {
    local search_dir="$1"
    local pattern="$2"
    local current_version="$3"

    local old_versions
    old_versions=$(find "$search_dir" -maxdepth 1 -type d -name "$pattern" ! -name "$current_version" 2>/dev/null)

    if [ -n "$old_versions" ]; then
        log_warn "Found old versions that can be removed manually:"
        echo "$old_versions"
    fi
}

# Update apt package list
update_apt() {
    log_info "Updating apt package list..."
    sudo apt update
}

# Upgrade system
upgrade_system() {
    log_info "Upgrading system packages..."
    sudo apt upgrade -y
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
        relative_install_dir="$HOME/.local"
    fi

    # Check if Blender is already installed
    if directory_exists "$install_dir"; then
        log_info "Blender $version is already installed at $install_dir"
        return 1
    fi

    log_info "Installing Blender $version..."

    # Change to temp directory
    cd /tmp || { log_error "Failed to change to /tmp directory"; exit 1; }

    # Download Blender
    download_file "$url" "$output_name"

    # Extract Blender
    log_info "Extracting Blender to $install_dir"

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
    log_info "Blender installation completed"

    return 0
}

# Check prerequisites
check_not_root
check_home_set
