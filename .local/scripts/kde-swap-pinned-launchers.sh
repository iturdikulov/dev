#!/usr/bin/env python3
"""
Swap two Icon-Only Task Manager pins in KDE Plasma (appletsrc + plasmashell --replace).

Finds the list index of each .desktop pin, swaps only those two entries (every other pin
keeps the same index), then writes launchers= back unchanged except for that pair exchange:
pin A takes B’s former slot and B takes A’s former slot.

Edits ~/.config/plasma-org.kde.plasma.desktop-appletsrc (override with PLASMA_APPLETSRC).

Usage:
  kde-swap-pinned-launchers [DESKTOP_A] [DESKTOP_B] [--no-replace|--no-reload] [--dry-run]

Arguments are full desktop ids (e.g. com.mitchellh.ghostty.desktop), compared to the part
after applications: (case-insensitive). Each id must appear exactly once in a given
launchers= row; if an id is pinned more than once, the script exits with the positions
listed so you can fix duplicates or pick different ids.

Defaults: ghostty-main.desktop  com.mitchellh.ghostty.desktop

  --no-replace / --no-reload  only edit appletsrc; do not run plasmashell --replace
  --dry-run                   show changed launchers= lines only; no writes
  --no-activate               after plasmashell --replace, do not invoke task slot shortcut
  --activate-slot N          which task-manager slot to activate (1 = leftmost, like Meta+1); default 1
  --activate-delay SEC       seconds to wait after replace before activate; default 4.5
"""
from __future__ import annotations

import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


def desktop_id_from_entry(entry: str) -> str:
    s = entry.strip()
    prefix = "applications:"
    if s.lower().startswith(prefix.lower()):
        return s[len(prefix) :]
    return s


def indices_for_id(items: list[str], want: str) -> list[int]:
    w = want.lower()
    out: list[int] = []
    for j, it in enumerate(items):
        if desktop_id_from_entry(it).lower() == w:
            out.append(j)
    return out


def swap_pair(items: list[str], desktop_a: str, desktop_b: str) -> tuple[list[str] | None, str | None]:
    """
    Swap the two entries matching desktop_a and desktop_b (one occurrence each required).
    Returns (new_list, error_message) on failure.
    """
    ia = indices_for_id(items, desktop_a)
    ib = indices_for_id(items, desktop_b)
    if not ia and not ib:
        return None, f"neither {desktop_a!r} nor {desktop_b!r} found in this pin row"
    if not ia:
        return None, f"{desktop_a!r} not found (positions of {desktop_b!r}: {[p + 1 for p in ib]})"
    if not ib:
        return None, f"{desktop_b!r} not found (positions of {desktop_a!r}: {[p + 1 for p in ia]})"
    if len(ia) > 1:
        pos = ", ".join(str(p + 1) for p in ia)
        return None, f"{desktop_a!r} appears {len(ia)} times (1-based positions: {pos}); pin it once or use a unique .desktop id"
    if len(ib) > 1:
        pos = ", ".join(str(p + 1) for p in ib)
        return None, f"{desktop_b!r} appears {len(ib)} times (1-based positions: {pos}); pin it once or use a unique .desktop id"
    i, j = ia[0], ib[0]
    if i == j:
        return None, "both ids refer to the same slot"
    new_items = items.copy()
    new_items[i], new_items[j] = new_items[j], new_items[i]
    return new_items, None


def process_line(line: str, desktop_a: str, desktop_b: str) -> tuple[str, bool, str | None]:
    if line.endswith("\r\n"):
        body, ending = line[:-2], "\r\n"
    elif line.endswith("\n"):
        body, ending = line[:-1], "\n"
    else:
        body, ending = line, ""

    m = re.match(r"^(\s*)launchers=(.*)$", body, re.DOTALL)
    if not m:
        return line, False, None
    indent, rest = m.group(1), m.group(2)
    items = [x.strip() for x in rest.split(",") if x.strip()]
    if not items:
        return line, False, None
    new_items, err = swap_pair(items, desktop_a, desktop_b)
    if err or new_items is None:
        return line, False, err
    new_line = f"{indent}launchers={','.join(new_items)}{ending}"
    return new_line, True, None


def plasmashell_replace() -> None:
    subprocess.Popen(
        ["plasmashell", "--replace"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def positive_int(s: str) -> int:
    v = int(s)
    if v < 1:
        raise argparse.ArgumentTypeError("must be >= 1")
    return v


def schedule_activate_task_manager_entry(slot: int, delay_sec: float) -> None:
    """
    After plasmashell restarts, shortcuts need a moment to register (same idea as Meta+1).
    Runs invokeShortcut in a detached shell so this script can exit immediately.
    """
    if slot < 1:
        return
    name = f"activate task manager entry {slot}"
    quoted = shlex.quote(name)
    delay_s = max(0.0, delay_sec)
    inner = (
        f"sleep {delay_s} ; "
        "for q in qdbus6 qdbus; do "
        'command -v "$q" >/dev/null 2>&1 || continue; '
        '"$q" org.kde.kglobalaccel /component/plasmashell '
        f"org.kde.kglobalaccel.Component.invokeShortcut {quoted} && break; "
        "done"
    )
    subprocess.Popen(
        ["bash", "-c", inner],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "desktop_a",
        nargs="?",
        default="ghostty-main.desktop",
        help="first .desktop id (default: ghostty-main.desktop)",
    )
    ap.add_argument(
        "desktop_b",
        nargs="?",
        default="com.mitchellh.ghostty.desktop",
        help="second .desktop id (default: com.mitchellh.ghostty.desktop)",
    )
    ap.add_argument(
        "--no-replace",
        "--no-reload",
        action="store_true",
        help="only edit appletsrc; do not run plasmashell --replace",
    )
    ap.add_argument("--dry-run", action="store_true", help="preview changes only")
    ap.add_argument(
        "--no-activate",
        action="store_true",
        help="after plasmashell --replace, do not run activate task manager entry shortcut",
    )
    ap.add_argument(
        "--activate-slot",
        type=positive_int,
        default=1,
        metavar="N",
        help="task manager slot to activate after replace (1=leftmost, like Meta+1); default 1",
    )
    ap.add_argument(
        "--activate-delay",
        type=float,
        default=4.5,
        metavar="SEC",
        help="seconds to wait after plasmashell --replace before activate; default 4.5",
    )
    args = ap.parse_args()

    def norm_desktop_arg(s: str) -> str:
        p = "applications:"
        if s.lower().startswith(p):
            return s[len(p) :]
        return s

    da = norm_desktop_arg(args.desktop_a)
    db = norm_desktop_arg(args.desktop_b)

    cfg = Path(os.environ.get("PLASMA_APPLETSRC", Path.home() / ".config/plasma-org.kde.plasma.desktop-appletsrc"))
    if not cfg.is_file():
        print(f"Config not found: {cfg}", file=sys.stderr)
        return 1

    lines = cfg.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    orig = list(lines)
    changed = 0
    for i, line in enumerate(lines):
        if not line.lstrip().startswith("launchers="):
            continue
        new_line, did, err = process_line(line, da, db)
        if err:
            print(f"{cfg}:{i + 1}: {err}", file=sys.stderr)
        if did:
            changed += 1
            lines[i] = new_line

    if changed == 0:
        print(
            f"No swap applied: no launchers= row could swap {da!r} and {db!r} "
            f"(each must appear exactly once per row).",
            file=sys.stderr,
        )
        return 2

    if args.dry_run:
        for i, line in enumerate(lines):
            if line != orig[i]:
                print(line, end="")
        print(f"(dry-run) {changed} launcher line(s) in {cfg}", file=sys.stderr)
        return 0

    bak = cfg.with_suffix(cfg.suffix + ".bak-swap-launchers")
    shutil.copy2(cfg, bak)
    cfg.write_text("".join(lines), encoding="utf-8")
    print(f"Updated {changed} launcher line(s) in {cfg}; backup: {bak}")

    if args.no_replace:
        return 0

    plasmashell_replace()
    print("Started plasmashell --replace (detached).")

    if not args.no_activate:
        schedule_activate_task_manager_entry(args.activate_slot, args.activate_delay)
        meta_hint = (
            f"Meta+{args.activate_slot}"
            if args.activate_slot <= 9
            else f"Meta+{args.activate_slot} (if bound)"
        )
        print(
            f"Scheduled activate task manager entry {args.activate_slot} "
            f"after {args.activate_delay:g}s (same as {meta_hint} when using default bindings)."
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
