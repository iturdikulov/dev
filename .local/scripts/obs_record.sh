#!/bin/sh

# TODO update sh PATH to avoid running programs with $HOME prefix?

# Checking obs is running
if ! pgrep -x "obs" > /dev/null
then
    obs &
    sleep 2
fi

$HOME/.local/bin/obs-cli record toggle

# Retry on error
retVal=$?
if [ $retVal -ne 0 ]; then
    sleep 5
    notify-send "Trying to record again"
    $HOME/.local/bin/obs-cli record toggle
fi
