#!/bin/sh

if [ "$#" -lt 1 ]; then
    echo "Usage: ./playlist_generator.sh [playlist_name] [optional: directory] [optional: new_base_path]"
    exit 1
fi

playlist_name=${1:-playlist}
music_folder=${2:-.}
new_base_path=$3

if [ ! -d "$music_folder" ]; then
    echo "Error: The specified music_folder does not exist or is not a directory."
    exit 1
fi

playlist_file="${playlist_name}.m3u8"
echo "#EXTM3U" > "$playlist_file"

find "$music_folder" -type f -iname "*.mp3" -o -iname "*.flac" -o -iname "*.mp4" -o -iname "*.mkv" | sort -V | while read -r music_file; do
    echo "#EXTINF:-1,$(basename "${music_file%.*}")" >> "$playlist_file"
    if [ -z "$new_base_path" ]; then
        echo "$music_file" >> "$playlist_file"
    else
        new_music_file="${new_base_path%/}/$(basename "$music_file")"
        echo "$new_music_file" >> "$playlist_file"
    fi
done

echo "Playlist generated successfully: $playlist_file"
