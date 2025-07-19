#!/bin/sh
if pidof -qx $1; then
    ~/.local/scripts/ww.sh -f "$2"
else
    $3
fi
