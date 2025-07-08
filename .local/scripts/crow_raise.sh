#!/bin/sh
if pidof -qx "cmus"; then
    ~/.local/scripts/ww.sh -f cmus -p cmus
else
    gtk-launch cmus.desktop
fi
