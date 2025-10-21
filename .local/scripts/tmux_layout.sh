#!/bin/bash
# Usage: ./tmux_layout.sh "window_name[:layout][:cmd1,cmd2,...]" ...
# ./tmux-tabs.sh "editor:main-vertical:nvim,htop" \
# "server:even-horizontal:python3 -m http.server" \
# "logs:tail -f /var/log/syslog"

if [ -z "$TMUX" ]; then
    echo "Error: This script must be run inside an active tmux session."
    exit 1
fi

for arg in "$@"; do
    # Split into window_name, layout, and commands
    IFS=':' read -r window_name layout cmds <<<"$arg"

    # Default layout
    [ -z "$layout" ] && layout="tiled"

    # Create the window
    tmux new-window -n "$window_name"

    # Split panes and run commands
    if [ -n "$cmds" ]; then
        # Split commands by comma
        IFS=',' read -ra cmd_array <<<"$cmds"

        # Run the first command in the main pane
        tmux send-keys -t "$window_name" "${cmd_array[0]}" C-m

        # For remaining commands, create a new pane for each
        for cmd in "${cmd_array[@]:1}"; do
            tmux split-window -t "$window_name" -h
            tmux send-keys -t "$window_name" "$cmd" C-m
        done

        # Apply layout after splitting panes
        tmux select-layout -t "$window_name" "$layout"
    fi
done
