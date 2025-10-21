#!/usr/bin/env bash

if [[ $# -eq 1 ]]; then
    selected=$1
else
    selected=$(
        (
         echo $HOME/; \
         echo $HOME/.config/yadm; \
         echo $HOME/.config/nvim; \
         echo $HOME/.local/scripts; \
         echo $HOME/.local/share; \
         fdfind --type=directory --max-depth=1 \
                --exclude='_*' \
                --follow \
                --one-file-system \
                --full-path "$HOME" \
        ~/ \
        ~/Pictures/personal/devices \
        ~/Media \
        ~/Videos \
        ~/Documents/personal \
        ~/Desktop \
        ~/Desktop/programming/bootdev \
        ~/Desktop/* )| fzf --tac)
fi

if [[ -z $selected ]]; then
    exit 0
fi

selected_name=$(basename "$selected" | tr . _)
tmux_running=$(pgrep tmux)

if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
    tmux new-session -s $selected_name -c $selected
    exit 0
fi

if ! tmux has-session -t=$selected_name 2> /dev/null; then
    if [[ -f "$selected/.tmuxp.yaml" ]]; then
        tmuxp load -d "$selected/.tmuxp.yaml"
    else
        tmux new-session -ds $selected_name -c $selected
    fi
fi

tmux switch-client -t $selected_name
