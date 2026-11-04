#!/usr/bin/env bash
# Win+R / gtk-launch com.mitchellh.ghostty.az → Ghostty + tmux session az-right
# (lazydocker / lazysql / lazyjournal tabs). Not tied to tmuxinator az.
set -euo pipefail

SESSION_RIGHT=az-right
CLASS=com.mitchellh.ghostty.az
ROOT="${HOME}/az"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/az-right-ghostty.lock"
# gtk-launch PATH минимальный; zsh -c ещё и переписывает PATH через .zshenv/.cargo/env.
# Не полагаемся на имя команды — резолвим абсолютные пути заранее.
DEFAULT_PATH="${HOME}/.local/go/bin:${HOME}/.local/scripts:${HOME}/.local/bin:${HOME}/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin"
tmux_path="$(tmux show-environment -g PATH 2>/dev/null | cut -d= -f2- || true)"
PATH_FOR_TABS="${DEFAULT_PATH}${tmux_path:+:$tmux_path}"

find_bin() {
  local bin
  bin="$(PATH="$PATH_FOR_TABS" command -v "$1" 2>/dev/null)" || {
    echo "az-right: '$1' not found (PATH=$PATH_FOR_TABS)" >&2
    return 1
  }
  printf '%s\n' "$bin"
}

LAZYDOCKER="$(find_bin lazydocker)"
LAZYSQL="$(find_bin lazysql)"
LAZYJOURNAL="$(find_bin lazyjournal)"

# Desktop may pass --foreground; ignore any args.
exec 9>"$LOCK"
flock -n 9 || exit 0

companion_running() {
  pgrep -f -- "ghostty.*--class=${CLASS}( |$)" >/dev/null 2>&1
}

pin_window() {
  local name="$1"
  tmux set-window-option -t "${SESSION_RIGHT}:${name}" automatic-rename off
  tmux set-window-option -t "${SESSION_RIGHT}:${name}" allow-rename off
}

window_exists() {
  tmux list-windows -t "$SESSION_RIGHT" -F '#{window_name}' | grep -qx "$1"
}

# -d: don't steal focus while creating
ensure_tab() {
  local name="$1" cmd="$2"
  window_exists "$name" && return 0
  tmux new-window -d -t "${SESSION_RIGHT}:" -c "$ROOT" -n "$name" \
    -e "PATH=${PATH_FOR_TABS}" \
    "$cmd"
  pin_window "$name"
}

if ! tmux has-session -t "$SESSION_RIGHT" 2>/dev/null; then
  tmux new-session -d -s "$SESSION_RIGHT" -c "$ROOT" -n lazydocker \
    -e "PATH=${PATH_FOR_TABS}" \
    "${LAZYDOCKER}; exec zsh -l"
  pin_window lazydocker
else
  # Legacy single-tab name from older script.
  if window_exists right-side; then
    tmux rename-window -t "${SESSION_RIGHT}:right-side" lazydocker 2>/dev/null || true
    pin_window lazydocker
  fi
fi

ensure_tab lazydocker "${LAZYDOCKER}; exec zsh -l"
ensure_tab lazysql "${LAZYSQL}; exec zsh -l"
ensure_tab lazyjournal "${LAZYJOURNAL}; exec zsh -l"

# Stable order via free high indices (direct :1/:2/:3 swaps collide)
tmux move-window -s "${SESSION_RIGHT}:lazydocker" -t "${SESSION_RIGHT}:91" 2>/dev/null || true
tmux move-window -s "${SESSION_RIGHT}:lazysql" -t "${SESSION_RIGHT}:92" 2>/dev/null || true
tmux move-window -s "${SESSION_RIGHT}:lazyjournal" -t "${SESSION_RIGHT}:93" 2>/dev/null || true
tmux move-window -s "${SESSION_RIGHT}:91" -t "${SESSION_RIGHT}:1" 2>/dev/null || true
tmux move-window -s "${SESSION_RIGHT}:92" -t "${SESSION_RIGHT}:2" 2>/dev/null || true
tmux move-window -s "${SESSION_RIGHT}:93" -t "${SESSION_RIGHT}:3" 2>/dev/null || true

# Default tab is lazydocker (first) — never fail the launch if rename raced
tmux select-window -t "${SESSION_RIGHT}:lazydocker" 2>/dev/null \
  || tmux select-window -t "${SESSION_RIGHT}:1" 2>/dev/null \
  || true

# Already open — run-or-raise focuses existing; do not spawn another Ghostty.
if companion_running; then
  exit 0
fi

# maximize=false: Deja Window restores DP-2 placement for this class.
exec ghostty \
  --gtk-single-instance=false \
  --quit-after-last-window-closed=true \
  --class="$CLASS" \
  --title=az-right \
  --maximize=false \
  --working-directory="$ROOT" \
  --command="tmux attach-session -t ${SESSION_RIGHT}" \
  --initial-command="tmux attach-session -t ${SESSION_RIGHT}"
