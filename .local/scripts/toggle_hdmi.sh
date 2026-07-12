#!/usr/bin/env bash
# Toggle HDMI-A-1 on KDE Plasma (Wayland) via kscreen-doctor.
# Saves the full multi-monitor layout before disable and restores it on enable.

set -euo pipefail

OUTPUT="${OUTPUT:-HDMI-A-1}"
ACTION="${1:-toggle}"
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/toggle-hdmi"
STATE_FILE="${STATE_DIR}/${OUTPUT}.json"

if ! command -v kscreen-doctor >/dev/null; then
    echo "kscreen-doctor not found" >&2
    exit 1
fi

get_json() {
    kscreen-doctor -j
}

query_output() {
    python3 -c '
import json
import sys

name = sys.argv[1]
data = json.loads(sys.argv[2])

for output in data.get("outputs", []):
    if output.get("name") == name:
        print("yes" if output.get("connected") else "no")
        print("yes" if output.get("enabled") else "no")
        sys.exit(0)

print("missing")
sys.exit(1)
' "$OUTPUT" "$(get_json)"
}

save_layout() {
    mkdir -p "$STATE_DIR"
    get_json >"$STATE_FILE"
}

restore_layout() {
    local enable_output="${1:-}"

    if [[ ! -f "$STATE_FILE" ]]; then
        echo "No saved layout at ${STATE_FILE}; enabling ${OUTPUT} only." >&2
        kscreen-doctor "output.${OUTPUT}.enable"
        return
    fi

    mapfile -t args < <(
        python3 - "$STATE_FILE" "$enable_output" <<'PY'
import json
import sys

state_file, enable_output = sys.argv[1:3]
with open(state_file, encoding="utf-8") as fh:
    data = json.load(fh)

rot_map = {1: "none", 2: "left", 4: "inverted", 8: "right"}

for output in data.get("outputs", []):
    if not output.get("connected"):
        continue

    name = output["name"]
    enabled = output.get("enabled", False)
    if enable_output and name == enable_output:
        enabled = True

    print(f"output.{name}.{'enable' if enabled else 'disable'}")
    if not enabled:
        continue

    pos = output["pos"]
    print(f"output.{name}.position.{pos['x']},{pos['y']}")
    print(f"output.{name}.mode.{output['currentModeId']}")

    scale = output["scale"]
    if scale == int(scale):
        scale = int(scale)
    print(f"output.{name}.scale.{scale}")

    rotation = rot_map.get(output.get("rotation", 1), "none")
    print(f"output.{name}.rotation.{rotation}")
PY
    )

    kscreen-doctor "${args[@]}"
}

disable_output() {
    save_layout
    kscreen-doctor "output.${OUTPUT}.disable"
}

case "$ACTION" in
    on|enable)
        restore_layout "$OUTPUT"
        ;;
    off|disable)
        disable_output
        ;;
    status)
        mapfile -t state < <(query_output)
        connected="${state[0]}"
        enabled="${state[1]}"
        echo "${OUTPUT}: connected=${connected} enabled=${enabled}"
        if [[ -f "$STATE_FILE" ]]; then
            echo "saved layout: ${STATE_FILE}"
        fi
        ;;
    toggle)
        mapfile -t state < <(query_output)
        if [[ "${state[0]}" == "missing" ]]; then
            echo "${OUTPUT}: output not found" >&2
            exit 1
        fi
        if [[ "${state[0]}" == "no" ]]; then
            echo "${OUTPUT}: not connected" >&2
            exit 1
        fi
        if [[ "${state[1]}" == "yes" ]]; then
            disable_output
        else
            restore_layout "$OUTPUT"
        fi
        ;;
    *)
        echo "Usage: ${0##*/} [on|off|toggle|status]" >&2
        echo "       OUTPUT=HDMI-A-1 ${0##*/} off" >&2
        exit 2
        ;;
esac
