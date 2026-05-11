#!/bin/bash

# --- CONFIGURATION ---
DEFAULT_ICON="application-x-executable"
MARKER="ROFI_WIN_$(date +%s)"
tmp_js="/tmp/rofi_kwin_$USER.js"

dbus_kwin() {
    dbus-send --session --dest=org.kde.KWin --print-reply=literal "$@"
}

# 1. Detect KWin Version
kwin_ver=$(dbus_kwin /KWin org.kde.KWin.supportInformation | awk '/KWin version:/ {print $3}')

if [ -z "$1" ]; then
    # --- MODE: LISTING ---
    
    # Create the script file (Faster than heredoc for D-Bus file reading)
    cat <<EOF > "$tmp_js"
    var list = [];
    var windows = workspace.windowList();
    for (var i=0; i < windows.length; i++) {
        var w = windows[i];
        if (w.caption && !w.skipTaskbar) {
            var iconHint = w.desktopFileName || w.resourceClass || "$DEFAULT_ICON";
            list.push(w.internalId + ":::" + w.caption + ":::" + iconHint);
        }
    }
    print("$MARKER:" + list.join("|"));
EOF

    # Load and get ID
    resp=$(dbus_kwin /Scripting org.kde.kwin.Scripting.loadScript "string:$tmp_js")
    id=$(echo "$resp" | awk '{print $2}')
    
    [[ "$kwin_ver" < "5.27.80" ]] && OBJ="/$id" || OBJ="/Scripting/Script$id"
    
    # Run
    dbus_kwin "$OBJ" org.kde.kwin.Script.run > /dev/null
    
    # Tiny pause for the log to register
    sleep 0.05

    # Extract data (Optimized journalctl call)
    data=$(journalctl --user _COMM=kwin_wayland _COMM=kwin_x11 -n 40 --no-pager | grep "$MARKER:" | tail -n 1 | sed "s/.*$MARKER://")

    if [ -z "$data" ]; then
        # Fallback for some systems where journalctl is slow or restricted
        # Re-try once with a slightly longer sleep if data is empty
        sleep 0.1
        data=$(journalctl --user _COMM=kwin_wayland _COMM=kwin_x11 -n 40 --no-pager | grep "$MARKER:" | tail -n 1 | sed "s/.*$MARKER://")
    fi

    # Fast display loop
    IFS='|' read -ra ADDR <<< "$data"
    for line in "${ADDR[@]}"; do
        [[ -z "$line" ]] && continue
        
        # Internal shell splitting (no awk/sed inside loop)
        win_id="${line%%:::*}"
        remainder="${line#*:::}"
        title="${remainder%%:::*}"
        icon="${remainder##*:::}"

        # Clean icon (Pure Bash)
        icon="${icon,,}"
        icon="${icon%.desktop}"
        icon_clean="${icon##*.}"
        icon_clean=$(echo "$icon_clean" | sed 's/[-._][0-9]\+$//')

        echo -e "${title}\0icon\x1f${icon_clean}\x1finfo\x1f${win_id}"
    done

    # Cleanup
    dbus_kwin "$OBJ" org.kde.kwin.Script.stop > /dev/null
    rm -f "$tmp_js"

else
    # --- MODE: SELECTION (Focus) ---
    WIN_ID="$ROFI_INFO"
    echo "var windows = workspace.windowList(); for (var i=0; i<windows.length; i++) { if(windows[i].internalId == '$WIN_ID') { workspace.activeWindow = windows[i]; break; } }" > "$tmp_js"
    
    resp=$(dbus_kwin /Scripting org.kde.kwin.Scripting.loadScript "string:$tmp_js")
    id=$(echo "$resp" | awk '{print $2}')
    [[ "$kwin_ver" < "5.27.80" ]] && OBJ="/$id" || OBJ="/Scripting/Script$id"
    
    dbus_kwin "$OBJ" org.kde.kwin.Script.run > /dev/null
    dbus_kwin "$OBJ" org.kde.kwin.Script.stop > /dev/null
    rm -f "$tmp_js"
fi
