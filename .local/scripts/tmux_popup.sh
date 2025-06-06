#!/bin/sh

set -e

CURRENT_PANE="$(tmux display-message -p -F "#{session_name}")"
if echo "$CURRENT_PANE" | grep -q '^popup.*'; then
    tmux detach-client
else
    if [ "$1" = "single" ]; then
        tmux popup -d '#{pane_current_path}' -xC -yC -w 60% -h 65% -E "tmux attach -t 'popup-$CURRENT_PANE' || tmux new -s 'popup-$CURRENT_PANE'" || true
    else
        tmux popup -xC -yC -w 80% -h 85% -E "tmux attach -t popup-master || tmux new -s popup-master" || true
    fi
fi
