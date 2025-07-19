#!/bin/sh

RECORDINGS_DIR="$HOME/Videos/record"
[ -d $RECORDINGS_DIR ] || echo "No $RECORDINGS_DIR directory found"
RECORDING="$RECORDINGS_DIR/$(ls -Art $RECORDINGS_DIR | tail -n 1)"
echo "Opening $RECORDING and copying to clipboard"
echo "$RECORDING" | wl-copy
mpv --loop-file=yes "$RECORDING"
