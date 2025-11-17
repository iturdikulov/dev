#!/bin/bash

if [[ -z "$1" ]]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

paid_till=$(whois "$1" | awk '/paid-till:/{print $2}')
expiry_ts=$(date -d "$paid_till" +%s)
now_ts=$(date +%s)
days=$(((expiry_ts - now_ts) / 86400))

if ((days < 30)); then
    echo "Warning: $1 expires in $days days!"
    exit 1
else
    echo "$1 expires in $days days!"
fi
