#!/usr/bin/env bash

if [[ $# -eq 1 ]]; then
    selected=$1
else
    selected=$(
        (
         echo ~/.config/yadm; \
         echo ~/.config/nvim; \
         echo ~/.local/scripts; \
         echo ~/.local/share; \
         fdfind --type=directory --max-depth=1 \
                --exclude='_*' \
                --one-file-system \
                --no-follow --full-path "$HOME" \
        ~/ \
        ~/Media \
        ~/Videos \
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
    tmux new-session -ds $selected_name -c $selected
fi

tmux switch-client -t $selected_name
