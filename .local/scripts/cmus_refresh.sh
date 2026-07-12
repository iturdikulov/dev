#!/bin/sh

real_cmus=/usr/bin/cmus
playlist_dir="$HOME/.config/cmus/playlists"
mkdir -p "$playlist_dir"

build_playlist() {
	dir="$1"
	name="$2"
	find "$dir" -type f | sort > "$playlist_dir/$name"
}

build_playlist "$HOME/Music/single" single
build_playlist "$HOME/Music/videos" videos
build_playlist "$HOME/Music/lofi" lofi
build_playlist "$HOME/Music/electronic" electronic
build_playlist "$HOME/Music/programming" programming
build_playlist "$HOME/Music/games" games
build_playlist "$HOME/Music/movie" movie
build_playlist "$HOME/Music/classic" classic

exec "$real_cmus" "$@"
