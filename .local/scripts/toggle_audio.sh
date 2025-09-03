#!/bin/bash
# pactl get-default-sink to determine sinks

sinks=($(pactl list sinks short | awk '/hdmi|analog/ {print $2}'))
current=$(pactl get-default-sink)

if [[ $current == "${sinks[0]}" ]]; then
    pactl set-default-sink "${sinks[1]}"
else
    pactl set-default-sink "${sinks[0]}"
fi

