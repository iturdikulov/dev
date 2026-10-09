#!/bin/bash

set -euo pipefail

get_sink_by_description() {
    local description=$1

    pactl list sinks | awk -v description="$description" '
        /^Sink #[0-9]+/ {
            name = ""
        }
        /^[[:space:]]+Name:/ {
            name = $2
        }
        /^[[:space:]]+Description:/ {
            value = $0
            sub(/^[[:space:]]+Description:[[:space:]]*/, "", value)
            if (value == description) {
                print name
                exit
            }
        }
    '
}

analog_sink=$(get_sink_by_description 'TE-C Analog Stereo')
line_out_sink=$(get_sink_by_description 'Starship/Matisse HD Audio Controller Analog Stereo')

if [[ -z $analog_sink || -z $line_out_sink ]]; then
    echo 'Не найдены оба аудиоустройства: TE-C Analog Stereo и Starship/Matisse HD Audio Controller Analog Stereo' >&2
    exit 1
fi

current=$(pactl get-default-sink)
target=$analog_sink
target_label='TE-C Analog Stereo'

if [[ $current == "$analog_sink" ]]; then
    target=$line_out_sink
    target_label='Starship Line Out'
fi

pactl set-default-sink "$target"

while read -r sink_input; do
    pactl move-sink-input "$sink_input" "$target"
done < <(pactl list short sink-inputs | awk '{print $1}')

if command -v gdbus >/dev/null 2>&1; then
    gdbus call \
        --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        'Audio' 0 '' 'Аудиовыход переключён' "$target_label" '[]' '{}' 3000 \
        >/dev/null 2>&1 || true
fi
