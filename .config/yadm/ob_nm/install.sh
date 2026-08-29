#!/usr/bin/env bash
# install.sh - run the numbered router stages in order.
# Optional convenience wrapper; each 0x_*.sh remains independently runnable.
# The numeric order guarantees all internet-dependent work (01-03) finishes
# before any network-disrupting change (04-09).

set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

mapfile -t stages < <(
    find "$DIR" -maxdepth 1 -type f -name '[0-9][0-9]_*.sh' -printf '%f\n' | sort
)

if ((${#stages[@]} == 0)); then
    echo "No stage scripts found in $DIR" >&2
    exit 1
fi

echo "Router stages: ${stages[*]}"
echo "Keys: Enter/y = run, n = skip, q = quit."

for stage in "${stages[@]}"; do
    while true; do
        read -r -p "Run $stage? [Y/n/q] " answer
        case "${answer:-y}" in
            [Yy]*)
                if bash "$DIR/$stage"; then
                    break
                fi
                read -r -p "$stage failed. Retry? [y/N] " retry
                [[ "$retry" =~ ^[Yy] ]] || break
                ;;
            [Nn]*) break ;;
            [Qq]*) exit 0 ;;
            *) echo "Please answer y, n, or q." ;;
        esac
    done
done

echo "Done."
