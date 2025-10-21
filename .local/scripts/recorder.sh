#!/bin/sh

# Record screen and audio using ffmpeg
mkdir -p "$HOME/Music/record"

OUTPUT="$HOME/Music/record/$(date +"%m%d%Y_%H%M%S")_record.wav"
MODEL="$HOME/.local/whisper/models/ggml-large-v3-turbo-q5_0.bin"
transcribtion=$(ffmpeg -f pulse -i default "$OUTPUT" && whisper-cli --model "$MODEL" --translate --no-prints "$OUTPUT")

# Save in ~/Wiki
echo "$transcribtion" >> "$HOME/Wiki/TODO_record.md"
echo "$transcribtion, saved in ~/Wiki/TODO_record.md"
