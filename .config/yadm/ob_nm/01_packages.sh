#!/usr/bin/env bash
# 01_packages.sh - install everything the router needs.
# Internet-dependent stage: run before any network reconfiguration.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

log_info "Installing router packages..."
install_packages \
    network-manager \
    dnsmasq \
    nftables \
    cron \
    iproute2 \
    curl \
    wget \
    gzip \
    nginx-light \
    unzip

log_info "Packages installed. No network services were reconfigured."
