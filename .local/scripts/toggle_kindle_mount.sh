#!/bin/sh
DEVICE="$1"
if [ -z "$DEVICE" ]; then
    echo "Usage: $0 <device_path_or_uuid>"
    exit 1
fi

if gio mount -l | grep -q "$DEVICE"; then
    gio mount -u "$DEVICE" && echo "Unmounted $DEVICE"
else
    gio mount "$DEVICE" && echo "Mounted $DEVICE"
fi
