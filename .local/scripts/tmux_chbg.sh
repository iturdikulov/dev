#!/bin/sh

[ -z "$TMUX_PANE" ] && exit
[ "$#" -eq 1 ] || exit 1

newstyle="$1"
oldstyle="$(tmux select-pane -g -t "$TMUX_PANE")"

tmux select-pane -P "$newstyle" -t "$TMUX_PANE"

( tail --pid="$PPID" -f /dev/null
  tmux select-pane -P "$oldstyle" -t "$TMUX_PANE" ) &
