#!/bin/sh

# Run zeal if not exists
pgrep zeal >/dev/null && ww.sh -t -f cmus || gtk-launch cmus
