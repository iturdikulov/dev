#!/usr/bin/env bash
# Clear common tool caches aligned with ~/.config/yadm/runs (Python/uv, Node, Go,
# Rust, Debian/apt, Docker, .NET). Safe to re-run; optional sections are skipped
# when the tool is missing.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=runs/utils.sh
source "$script_dir/runs/utils.sh"

with_docker=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--docker]

  Clears caches for uv, pip/Python, npm/pnpm/yarn, Go, Rust (Cargo download
  caches), APT (needs sudo), and .NET NuGet if installed.

  --docker   Also prune Docker build cache (docker builder prune).

EOF
}

while (($# > 0)); do
    case "$1" in
        --docker)
            with_docker=1
            shift
            ;;
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

cleanup_uv() {
    if command_exists uv; then
        log_info "Cleaning uv cache..."
        uv cache clean || log_warn "uv cache clean failed"
    else
        log_warn "uv not found, skipping"
    fi
}

cleanup_python_pip() {
    if command_exists python3 && python3 -m pip cache dir &>/dev/null; then
        log_info "Purging pip cache (python3 -m pip)..."
        python3 -m pip cache purge || log_warn "pip cache purge failed"
    else
        log_warn "pip cache not available, skipping"
    fi
}

cleanup_node() {
    if command_exists npm; then
        log_info "Cleaning npm cache..."
        npm cache clean --force || log_warn "npm cache clean failed"
    else
        log_warn "npm not found, skipping"
    fi

    if command_exists pnpm; then
        log_info "Pruning pnpm store..."
        pnpm store prune || log_warn "pnpm store prune failed"
    fi

    if command_exists yarn; then
        log_info "Cleaning yarn cache..."
        yarn cache clean || log_warn "yarn cache clean failed"
    fi
}

cleanup_go() {
    if command_exists go; then
        log_info "Cleaning Go build/module/test caches..."
        go clean -cache -modcache -testcache || log_warn "go clean failed"
    else
        log_warn "go not found, skipping"
    fi
}

cleanup_rust() {
    local cargo_home="${CARGO_HOME:-$HOME/.cargo}"

    if [[ ! -d "$cargo_home" ]]; then
        log_warn "Cargo home missing ($cargo_home), skipping Rust caches"
        return 0
    fi

    # Prefer cargo-cache when installed (cargo install cargo-cache).
    if command_exists cargo-cache; then
        log_info "Running cargo-cache --autoclean..."
        cargo-cache --autoclean || log_warn "cargo-cache failed"
        return 0
    fi

    log_info "Removing Cargo registry tarball and git dependency caches..."
    local d
    for d in "$cargo_home/registry/cache" "$cargo_home/git/db"; do
        if [[ -d "$d" ]]; then
            find "$d" -mindepth 1 -delete 2>/dev/null || log_warn "Could not fully clean $d"
        fi
    done
}

cleanup_apt() {
    log_info "Cleaning APT caches (sudo)..."
    if sudo apt-get clean && sudo apt-get autoclean -y; then
        log_info "APT cache cleanup done"
    else
        log_warn "APT cleanup failed or sudo denied"
    fi
}

cleanup_dotnet() {
    if command_exists dotnet; then
        log_info "Clearing .NET NuGet locals..."
        dotnet nuget locals all --clear || log_warn "dotnet nuget locals clear failed"
    else
        log_warn "dotnet not found, skipping"
    fi
}

cleanup_docker() {
    if ((!with_docker)); then
        return 0
    fi
    if command_exists docker; then
        log_info "Pruning Docker builder cache..."
        docker builder prune -f || log_warn "docker builder prune failed"
    else
        log_warn "docker not found, skipping"
    fi
}

main() {
    log_info "Starting cache cleanup"
    cleanup_uv
    cleanup_python_pip
    cleanup_node
    cleanup_go
    cleanup_rust
    cleanup_dotnet
    cleanup_docker
    cleanup_apt
    log_info "Finished cache cleanup"
}

main "$@"
