#!/usr/bin/env python3
"""Ctrl+Print: GNOME portal area screenshot → ~/tmp/screens, path to clipboard.

Uses xdg-desktop-portal-gnome (same interactive UI as the built-in Print key).
org.gnome.Shell.Screenshot.* is AccessDenied for external callers on GNOME 48.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
from datetime import datetime
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

OUTDIR = os.path.expanduser("~/tmp/screens")
TIMEOUT_SEC = 300


def _uri_to_path(uri: str) -> str:
    parsed = urlparse(uri)
    if parsed.scheme != "file":
        raise ValueError(f"unexpected uri: {uri}")
    return unquote(parsed.path)


def _copy_path(path: str) -> None:
    subprocess.run(
        ["wl-copy", "--type", "text/plain"],
        input=path.encode(),
        check=True,
    )


def take_screenshot() -> str | None:
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    handle_token = f"azshot{os.getpid()}{int(time.time())}"
    sender = bus.get_unique_name()
    if not sender:
        raise RuntimeError("no D-Bus unique name")
    sender_token = sender[1:].replace(".", "_")
    request_path = (
        f"/org/freedesktop/portal/desktop/request/{sender_token}/{handle_token}"
    )

    loop = GLib.MainLoop()
    outcome: dict = {}

    def on_response(_conn, _sender, _path, _iface, _signal, params):
        response_code, results = params.unpack()
        outcome["code"] = int(response_code)
        outcome["results"] = dict(results)
        loop.quit()

    bus.signal_subscribe(
        None,
        "org.freedesktop.portal.Request",
        "Response",
        request_path,
        None,
        Gio.DBusSignalFlags.NONE,
        on_response,
    )

    options = {
        "handle_token": GLib.Variant("s", handle_token),
        "interactive": GLib.Variant("b", True),
        "modal": GLib.Variant("b", True),
    }
    proxy = Gio.DBusProxy.new_sync(
        bus,
        Gio.DBusProxyFlags.NONE,
        None,
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Screenshot",
        None,
    )
    proxy.call_sync(
        "Screenshot",
        GLib.Variant("(sa{sv})", ("", options)),
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )

    GLib.timeout_add_seconds(TIMEOUT_SEC, loop.quit)
    loop.run()

    if "code" not in outcome:
        return None
    if outcome["code"] != 0:
        # 1 = user cancelled / interaction failed
        return None

    uri = outcome["results"].get("uri")
    if not uri:
        return None
    return _uri_to_path(str(uri))


def main() -> int:
    os.makedirs(OUTDIR, exist_ok=True)
    try:
        src = take_screenshot()
    except Exception as exc:  # noqa: BLE001 — log and exit for hotkey use
        print(f"screenshot failed: {exc}", file=sys.stderr)
        return 1

    if not src or not os.path.isfile(src):
        return 0

    dest = os.path.join(OUTDIR, datetime.now().strftime("%Y%m%d-%H%M%S.png"))
    if os.path.abspath(src) != os.path.abspath(dest):
        # Portal may drop into ~/Pictures/Screenshots; move into our tree.
        shutil.move(src, dest)
    else:
        dest = src

    _copy_path(dest)
    print(dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
