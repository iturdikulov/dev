#!/usr/bin/env zsh

if command -v ifconfig >/dev/null; then
  ifconfig ${NET_IF} | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'
elif command -v ip >/dev/null; then
  ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/'
else
  >&2 echo "No easy way to grab your IP"
  exit 1
fi

dig +short "myip.opendns.com" "@resolver1.opendns.com"
