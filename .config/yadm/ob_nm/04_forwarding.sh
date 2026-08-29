#!/usr/bin/env bash
# 04_forwarding.sh - enable IPv4/IPv6 packet forwarding.
# First network stage; safe on its own but grouped with the disruptive steps.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/lib.sh"

link_system_file "etc/sysctl.d/99-ob-router.conf"

log_info "Applying sysctl settings..."
sudo sysctl --system

log_info "IP forwarding enabled."
