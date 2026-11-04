#!/usr/bin/env bash
# Sync tmux windows in session az to a multi-select of ~/az/packages/*.
# Open packages are pre-selected; confirm opens missing + graceful-closes deselected.
# List order: rarely/never used at top, most recent at bottom (near fzf prompt).
set -euo pipefail

AZ_ROOT="${HOME}/az"
PACKAGES_DIR="${AZ_ROOT}/packages"
STATE_DIR="${HOME}/.local/state/az-packages"
HISTORY_FILE="${STATE_DIR}/history"
KILL_WIN="${HOME}/.local/scripts/tmux_graceful_kill_window.sh"

resolve_session() {
  local current
  current="$(tmux display-message -p '#{session_name}' 2>/dev/null || true)"
  if [[ "$current" == "az" ]]; then
    printf '%s\n' az
    return
  fi
  if tmux has-session -t az 2>/dev/null; then
    printf '%s\n' az
    return
  fi
  tmux display-message -d 2000 "az-packages: no az session"
  exit 1
}

# MRU file: one name per line, last occurrence = most recent.
# stdout: unique names oldest → newest
read_mru() {
  [[ -f "$HISTORY_FILE" ]] || return 0
  awk 'NF { last[$0]=NR; order[NR]=$0 } END {
    n = 0
    for (i = 1; i <= NR; i++) {
      p = order[i]
      if (last[p] == i) out[++n] = p
    }
    for (i = 1; i <= n; i++) print out[i]
  }' "$HISTORY_FILE"
}

# Append selected packages as newest; keep file bounded.
touch_mru() {
  mkdir -p "$STATE_DIR"
  local p
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    printf '%s\n' "$p" >>"$HISTORY_FILE"
  done
  # compact to unique oldest→newest, max 200 lines
  if [[ -f "$HISTORY_FILE" ]]; then
    local tmp
    tmp="$(mktemp)"
    read_mru | tail -n 200 >"$tmp"
    mv "$tmp" "$HISTORY_FILE"
  fi
}

pkg_mtime() {
  stat -c '%Y' "${PACKAGES_DIR}/$1" 2>/dev/null || echo 0
}

session="$(resolve_session)"

mapfile -t all_packages < <(
  find "$PACKAGES_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name tmp ! -name '.*' -printf '%f\n'
)

if ((${#all_packages[@]} == 0)); then
  tmux display-message -d 2000 "az-packages: no packages under ${PACKAGES_DIR}"
  exit 1
fi

declare -A is_pkg=()
for p in "${all_packages[@]}"; do
  is_pkg["$p"]=1
done

mapfile -t mru < <(read_mru)
declare -A in_mru=()
mru_alive=()
for name in "${mru[@]}"; do
  [[ -n "${is_pkg[$name]:-}" ]] || continue
  in_mru["$name"]=1
  mru_alive+=("$name")
done

# Never/rarely used first (by dir mtime), then MRU oldest→newest at bottom.
# Note: printf '%s\n' with zero args still prints a blank line — skip empty MRU.
mapfile -t packages < <(
  {
    for p in "${all_packages[@]}"; do
      [[ -z "${in_mru[$p]:-}" ]] || continue
      printf '%s\t%s\n' "$(pkg_mtime "$p")" "$p"
    done | sort -n -k1,1 | cut -f2-
    if ((${#mru_alive[@]} > 0)); then
      printf '%s\n' "${mru_alive[@]}"
    fi
  }
)

mapfile -t open_wins < <(tmux list-windows -t "$session" -F '#{window_name}')
declare -A open_pkg=()
for w in "${open_wins[@]}"; do
  [[ -n "$w" && -n "${is_pkg[$w]:-}" ]] && open_pkg["$w"]=1
done

toggle_parts=()
for i in "${!packages[@]}"; do
  pkg="${packages[$i]}"
  [[ -n "$pkg" ]] || continue
  if [[ -n "${open_pkg[$pkg]:-}" ]]; then
    line=$((i + 1))
    toggle_parts+=("pos(${line})+toggle")
  fi
done

fzf_bind_args=()
if ((${#toggle_parts[@]} > 0)); then
  IFS=+
  fzf_bind_args+=(--bind "load:${toggle_parts[*]}")
  unset IFS
fi

set +e
selected="$(
  printf '%s\n' "${packages[@]}" | fzf-tmux -p 60%,60% \
    --multi --no-sort --ansi \
    --border-label ' az packages ' \
    --prompt '󰏖  ' \
    --header '  tab multi  enter sync  esc abort' \
    --bind 'tab:toggle+down,btab:toggle+up' \
    "${fzf_bind_args[@]}"
)"
fzf_status=$?
set -e

# Esc / Ctrl-C — no changes
if ((fzf_status == 130 || fzf_status == 2)); then
  exit 0
fi
# status 1 with empty = no match; treat as abort
if ((fzf_status == 1)); then
  exit 0
fi

declare -A want=()
selected_list=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  want["$line"]=1
  selected_list+=("$line")
done <<<"$selected"

# Close deselected package windows first
for w in "${!open_pkg[@]}"; do
  if [[ -z "${want[$w]:-}" ]]; then
    "$KILL_WIN" "${session}:${w}"
  fi
done

# Open missing selected packages
for p in "${packages[@]}"; do
  [[ -n "${want[$p]:-}" ]] || continue
  [[ -n "${open_pkg[$p]:-}" ]] && continue
  tmux new-window -t "${session}:" -n "$p" -c "${PACKAGES_DIR}/${p}" nvim
done

# Selected set = current MRU (newest last, preserve fzf order ≈ user attention)
if ((${#selected_list[@]} > 0)); then
  touch_mru "${selected_list[@]}"
fi
