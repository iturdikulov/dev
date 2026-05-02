#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
runs_dir="$script_dir/runs"
include_gui=1
include_ufw=1
blacklist_value=""

usage() {
    cat <<EOF
Usage: $0 [--no-gui] [--no-ufw] [--blacklist "name1 name2 ..."]

Keys: Enter/y = run or retry, n = skip, p = run previous, q = quit, Ctrl+C = stop active runner.
EOF
}

while (($# > 0)); do
    case "$1" in
        --no-gui)
            include_gui=0
            shift
            ;;
        --no-ufw)
            include_ufw=0
            shift
            ;;
        --blacklist)
            if (($# < 2)); then
                echo "Missing value for --blacklist" >&2
                usage >&2
                exit 2
            fi
            blacklist_value="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

declare -A blacklisted=()
for name in $blacklist_value; do
    blacklisted["$name"]=1
done

run_runner() {
    local name="$1"
    local runner="$runs_dir/$name"

    if [[ ! -x "$runner" || ! -f "$runner" ]]; then
        echo "Runner is missing or not executable: $runner" >&2
        return 1
    fi

    echo
    echo "==> Running $name"
    local status

    trap ':' INT
    set +e
    (
        trap - INT
        if ((include_ufw == 0)); then
            export YADM_IS_WSL=1
        fi
        "$runner"
    )
    status=$?
    set -e
    trap - INT
    return "$status"
}

prompt() {
    local message="$1"
    local answer

    while true; do
        read -r -p "$message" answer
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]|"") printf '%s\n' "y"; return ;;
            [Nn]|[Nn][Oo]) printf '%s\n' "n"; return ;;
            [Pp]) printf '%s\n' "p"; return ;;
            [Qq]) printf '%s\n' "q"; return ;;
            *) echo "Please answer y, n, p, or q." >&2 ;;
        esac
    done
}

print_key_note() {
    printf '\033[90m%s\033[0m\n' "Keys: Enter/y = run or retry, n = skip, p = run previous, q = quit, Ctrl+C = stop active runner."
}

run_with_retry() {
    local name="$1"
    local action

    while true; do
        if run_runner "$name"; then
            return 0
        fi

        action="$(prompt "Retry $name? [Y/n/p/q] ")"
        case "$action" in
            y) ;;
            n) return 0 ;;
            p) ;;
            q) return 3 ;;
        esac
    done
}

mapfile -t runners < <(
    find "$runs_dir" -maxdepth 1 -type f -executable -printf '%f\n' |
        sort
)

previous_runner=""
print_key_note

for name in "${runners[@]}"; do
    if [[ "$name" == .* || "$name" == "utils.sh" ]]; then
        continue
    fi
    if ((include_gui == 0)) && [[ "$name" == *_gui ]]; then
        continue
    fi
    if [[ -n "${blacklisted[$name]:-}" ]]; then
        continue
    fi

    while true; do
        action="$(prompt "Run $name? [Y/n/p/q] ")"
        case "$action" in
            y)
                previous_runner="$name"
                result=0
                run_with_retry "$name" || result=$?
                case "$result" in
                    0) break ;;
                    3) exit 0 ;;
                    *) exit "$result" ;;
                esac
                ;;
            n)
                break
                ;;
            p)
                if [[ -z "$previous_runner" ]]; then
                    echo "No previous runner yet."
                    continue
                fi
                result=0
                run_with_retry "$previous_runner" || result=$?
                case "$result" in
                    0) ;;
                    3) exit 0 ;;
                    *) exit "$result" ;;
                esac
                ;;
            q)
                exit 0
                ;;
        esac
    done
done
