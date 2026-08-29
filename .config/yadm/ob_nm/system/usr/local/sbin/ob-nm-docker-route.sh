#!/bin/sh
# Keep Docker bridge traffic out of Mihomo auto-redirect (TCP) and policy routing.

set -eu

add_rule() {
	lookup=$1
	priority=$2
	shift 2
	if ! ip rule show | grep -Fq "$* lookup $lookup"; then
		ip rule add "$@" lookup "$lookup" priority "$priority"
	fi
}

add_rule main 100 from 172.16.0.0/12
add_rule main 98 to 172.16.0.0/12

if nft list chain inet mihomo prerouting >/dev/null 2>&1; then
	if ! nft list chain inet mihomo prerouting | grep -Fq 'ip saddr 172.16.0.0/12 return'; then
		nft insert rule inet mihomo prerouting ip saddr 172.16.0.0/12 return
	fi
fi
