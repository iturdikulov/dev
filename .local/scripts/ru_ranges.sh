#!/usr/bin/env bash

# Download the IP ranges
URL="https://raw.githubusercontent.com/ipverse/rir-ip/refs/heads/master/country/ru/ipv4-aggregated.txt"
TMP_FILE=$(mktemp)
OUT_FILE=${1:-amnezia_wg_ru_ips.json}
wget2 "$URL" -O "$TMP_FILE"

jq -R -s 'split("\n") | map(select(. != "")) | map({"hostname": ., "ip": ""})' "$TMP_FILE" > /tmp/agg.json

# Download geo files
URL="https://github.com/v2fly/domain-list-community/releases/download/20251228162640/dlc.dat"
wget2 "$URL" -O "/tmp/dlc.dat"

geoview -type geosite -input "/tmp/dlc.dat" -list yandex,vk,category-finance,binance,category-ru,category-gov-ru,category-media-ru,rutube,mailru,avito,2ch,docker,amazon,ebay,alibaba,ozon,google,google-play,google-trust-services,youtube,twitch,category-entertainment,github,gitlab,category-media,telegram,reddit -output "/tmp/geosite.txt"
jq -R -s 'split("\n") | map(select(. != "")) | map({"hostname": ., "ip": ""})' "/tmp/geosite.txt" > /tmp/geo.json

jq -s add /tmp/agg.json /tmp/geo.json > "$OUT_FILE"

echo "Generated $OUT_FILE"

# Clean up

