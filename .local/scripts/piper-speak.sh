#!/usr/bin/env bash

LOCK_FILE="/tmp/my_script.lock"
RU_PATTERN='[А-Яа-яЁё]+'  # Regex pattern for Cyrillic characters

# Check if another instance is already running
if [ -e "$LOCK_FILE" ] && kill -0 $(cat "$LOCK_FILE"); then
  echo "Another instance is already running."
  exit 1
fi

# Create the lock file
echo $$ > "$LOCK_FILE"

speak(){
    local lang="${1:-EN}"

    if [[ $lang == "RU" ]]; then
        local model="$HOME/.local/share/piper_model/ru_RU-ruslan-medium.onnx"
    else
        local model="$HOME/.local/share/piper_model/en_US-lessac-medium.onnx"
    fi

    "$HOME/.local/bin/piper" --length_scale 1.2 --model $model --output-raw | ffplay -hide_banner -loglevel panic -i -f s16le -ar 22050 -autoexit -nodisp -
}

if [ $# -eq 0 ]
  then
    # Core logic
    text=$(wl-paste)
else
    if [[ $1 == "stdin" ]]; then
        text=$(</dev/stdin)
    else
        text="$@"
    fi

    echo $text
fi

if [[ "$text" =~ $RU_PATTERN ]]; then
    echo "$text" | speak "RU"
else
    echo "$text" | speak
fi

# Remove the lock file
rm "$LOCK_FILE"
