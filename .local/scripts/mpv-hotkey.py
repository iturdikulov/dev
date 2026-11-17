#!/usr/bin/env python3
"""Управляет mpv по IPC-сокету — точка входа для глобальных клавиш GNOME.

Сокет задан в mpv.conf и в обёртке ~/.local/bin/mpv (`input-ipc-server`),
поэтому активное окно mpv не нужно. Если mpv не запущен, действие уходит
другим MPRIS-плеерам через playerctl: своего MPRIS у mpv нет.
"""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys

SOCKET_PATH = os.environ.get("MPV_IPC_SOCKET", "/tmp/mpvsocket")
TIMEOUT_SEC = 2.0
# Предохранитель от бесконечного чтения, если ответ потерялся среди событий.
MPV_REPLY_MAX_LINES = 64


def mpv_command(command: list[str]) -> bool:
    """Отправляет одну команду в mpv. False — сокета нет или он мёртв."""
    if not os.path.exists(SOCKET_PATH):
        return False

    payload = json.dumps({"command": command}) + "\n"
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(TIMEOUT_SEC)
    try:
        sock.connect(SOCKET_PATH)
        sock.sendall(payload.encode())
        # mpv присылает события ({"event": ...}) в ту же ленту, поэтому ответ
        # ищем по полю request_id, а не по первой строке.
        reader = sock.makefile("rb")
        for _ in range(MPV_REPLY_MAX_LINES):
            line = reader.readline()
            if not line:
                return False
            reply = json.loads(line)
            if "request_id" in reply:
                return reply.get("error") == "success"
        return False
    except (OSError, ValueError):
        return False
    finally:
        sock.close()
    return False


def playerctl(args: list[str]) -> None:
    if shutil.which("playerctl"):
        subprocess.run(
            ["playerctl", *args],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="action", required=True)

    subparsers.add_parser("play-pause", help="пауза/продолжить")
    seek = subparsers.add_parser("seek", help="перемотка относительно текущей позиции")
    seek.add_argument("seconds", type=int, help="секунды: -5 назад, 5 вперёд")

    args = parser.parse_args()

    if args.action == "play-pause":
        if not mpv_command(["cycle", "pause"]):
            playerctl(["play-pause"])
        return 0

    seconds = args.seconds
    if not mpv_command(["seek", str(seconds), "relative"]):
        # playerctl требует суффикс направления: "5+" вперёд, "5-" назад.
        playerctl(["position", f"{abs(seconds)}{'+' if seconds >= 0 else '-'}"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
