#!/bin/bash
# source: https://raw.githubusercontent.com/academo/ww-run-raise/refs/heads/master/ww

TOGGLE="false"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
	-c | --command)
		COMMAND="$2"
		shift # past argument
		shift # past value
		;;
	-f | --filter)
		FILTERBY="$2"
		shift # past argument
		shift # past value
		;;
	-p | --process)
		PROCESS="$2"
		shift # past argument
		shift # past value
		;;
	-fa | --filter-alternative)
		FILTERALT="$2"
		shift # past argument
		shift # past value
		;;
	-t | --toggle)
		TOGGLE="true"
		shift # past argument
		;;
	-ia | --info-active)
		INFO_ACTIVE="1"
		shift # past argument
		;;
	-u | --current-user)
		CURRENTUSERONLY="true"
		shift # past argument
		;;
	-h | --help)
		HELP="1"
		shift # past argument
		shift # past value
		;;
	*)                  # unknown option
		POSITIONAL+=("$1") # save it in an array for later
		shift              # past argument
		;;
	esac
done

if [[ -z "$PROCESS" ]]; then
	PROCESS=$COMMAND
fi

set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ -n "$HELP" ]]; then
	cat <<EOF
ww. Utility to launch a window (or raise it, if it was minimized), or to show information about the active window, or to perform other operations with windows in KDE Plasma. It interacts with KWin using KWin scripts and it is compatible with X11 and Wayland.

Parameters:

-h  --help                show this help
-ia --info-active         show information about the active window. Using this parameter, this program can be periodically called from
                          other programs, so the user is able to know how much time he/she spends using particular windows, or the user
                          is able to stop (in order to save CPU use, bandwith or downloaded MBs) programs when they are not in the
                          foreground, etc.
-f  --filter              filter by window class
-fa --filter-alternative  filter by window title (caption)
-t  --toggle              also minimize the window if it is already active
-c  --command             command to check if running and run if no process is found
-p --process overide the process name used when checking if running, defaults to --command
-u --current-user         will only search processes of the current user. requires loginctl
EOF
	exit 0
fi

dbus_kwin () {
    dbus-send --session --dest=org.kde.KWin --print-reply=literal "$@"
}

function get_kwin_version() {
    kwinSupportInfo="$(dbus_kwin /KWin org.kde.KWin.supportInformation)" || exit 1
    kwinVersion="$(awk '/KWin version:/ {print $3}' <<< "$kwinSupportInfo")" || exit 1
    echo "$kwinVersion"
}

if [[ -n "$INFO_ACTIVE" ]]; then
    kwinVersion=$(get_kwin_version)
    kwinMajorVersion="$(awk -F"." '{print $1}' <<< "$kwinVersion")" || exit 1
    # This feature needs at least this KWin version
    readonly minimumVersion=6 || exit 1
    if [[ "$kwinMajorVersion" -lt "$minimumVersion" ]]; then
        echo "ERROR: This feature needs KWin $minimumVersion or later." >&2
        exit 1
    fi

    # This way is similar to the one used on https://discuss.kde.org/t/xdotool-replacement-on-wayland/7242/9
    jsFile="$(mktemp)" || exit 1   # It is the file where the javascript code is going to be saved
    echo "print(\"$jsFile\",workspace.activeWindow.internalId);" > "$jsFile" || exit 1

    scriptId_response="$(dbus_kwin /Scripting org.kde.kwin.Scripting.loadScript "string:$jsFile")" || exit 1
    scriptId=$(awk '{print $2}' <<< "$scriptId_response") || exit 1
    timestamp="$(date +"%Y-%m-%d %H:%M:%S")" || exit 1
    # Starts the script
    dbus_kwin "/Scripting/Script$scriptId" org.kde.kwin.Script.run || exit 1

    # Uses some arguments that are also seen on https://github.com/jinliu/kdotool/blob/master/src/main.rs
    outputJournalctl="$(journalctl --since "$timestamp" --user --user-unit=plasma-kwin_wayland.service --user-unit=plasma-kwin_x11.service --output=cat -g "js: $jsFile")" || exit 1
    # Uses `awk` separately in order to avoid masking a return value, as Shellcheck recommends
    windowId="$(awk '{print $3}' <<< "$outputJournalctl")" || exit 1
    # Stops the script
    dbus_kwin "/Scripting/Script$scriptId" org.kde.kwin.Script.stop || exit 1

    if command -v qdbus 2>&1 >/dev/null; then
        qdbus_bin=qdbus
    elif command -v qdbus6 2>&1 >/dev/null; then
        # On Arch some users might only have qt6-tools installed
        qdbus_bin=qdbus6
    else
        echo "'qdbus' or 'qdbus6' command not found, aborting."
        exit 1
    fi

    # Shows the information about that window
    $qdbus_bin org.kde.KWin /KWin org.kde.KWin.getWindowInfo "$windowId" || exit 1

    exit 0
fi

SCRIPT_TEMPLATE=$(
	cat <<EOF
function kwinactivateclient(clientClass, clientCaption, toggle) {
    var clients = workspace.clientList ? workspace.clientList() : workspace.windowList();
    var activeWindow = workspace.activeClient || workspace.activeWindow;
    var compareToCaption = new RegExp(clientCaption || '', 'i');
    var compareToClass = clientClass;
    var isCompareToClass = clientClass.length > 0;
    var matchingClients = [];

    for (var i = 0; i < clients.length; i++) {
        var client = clients[i];
        var classCompare = (isCompareToClass && client.resourceClass == compareToClass);
        var captionCompare = (!isCompareToClass && compareToCaption.exec(client.caption));
        if (classCompare || captionCompare) {
            matchingClients.push(client);
        }
    }

    if (matchingClients.length === 1) {
        var client = matchingClients[0];
        if (activeWindow !== client) {
            setActiveClient(client);
        } else if (toggle) {
            client.minimized = !client.minimized;
        }
    } else if (matchingClients.length > 1) {

        matchingClients.sort(function (a, b) {
            return a.stackingOrder - b.stackingOrder;
        });
        const client = matchingClients[0];
        setActiveClient(client);
    }
}

function setActiveClient(client){
    if (workspace.activeClient !== undefined) {
        workspace.activeClient = client;
    } else {
        workspace.activeWindow = client;
    }
}
kwinactivateclient('CLASS_NAME', 'CAPTION_NAME', TOGGLE);
EOF
)

# ensure the script file exists
function ensure_script {
	if [[ ! -f SCRIPT_PATH ]]; then
		if [[ ! -d "$SCRIPT_FOLDER" ]]; then
			mkdir -p "$SCRIPT_FOLDER"
		fi
		SCRIPT_CONTENT=${SCRIPT_TEMPLATE/CLASS_NAME/$1}
		SCRIPT_CONTENT=${SCRIPT_CONTENT/CAPTION_NAME/$2}
        SCRIPT_CONTENT=${SCRIPT_CONTENT/TOGGLE/$3}
		echo "$SCRIPT_CONTENT" >"$SCRIPT_PATH"
	fi
}

# Check if a version string is between two inclusive versions.
function ver_between() {
    # args: min, actual, max
    printf '%s\n' "$@" | sort -C -V
}

# Check if a version string is lower than another.
function ver_lt() {
    printf '%s\n' "$1" "$2" | sort -C -V
}

if [[ -z "$FILTERBY" && -z "$FILTERALT" ]]; then
	echo "If you want that this program find a window, you need to specify a window filter — either by class (\`-f\`) or by title (\`-fa\`). More information can be seen if this script is called using the \`--help\` parameter."
	exit 1
fi

USER_FILTER=""
if [[ -n "$CURRENTUSERONLY" ]] && command -v loginctl >/dev/null 2>&1; then
	if command -v loginctl >/dev/null 2>&1; then
   	session_id=$(loginctl show-seat seat0 -p ActiveSession --value)
   	user_id=$(loginctl show-session "$session_id" -p User --value)
   	USER_FILTER="-u $user_id"
	fi
fi

# Note: In this case, `$USER_FILTER` must not have quotes around it.
# shellcheck disable=SC2086
IS_RUNNING=$(pgrep $USER_FILTER -o -a -f "$PROCESS" --ignore-ancestors)

if [[ -n "$IS_RUNNING" || -n "$FILTERALT" ]]; then
	# trying for XDG_CONFIG_HOME first.
	# shellcheck disable=SC2154
	SCRIPT_FOLDER_ROOT=$XDG_CONFIG_HOME
	if [[ -z $SCRIPT_FOLDER_ROOT ]]; then
		# fallback to the home folder
		SCRIPT_FOLDER_ROOT=$HOME
	fi

	SCRIPT_FOLDER="$SCRIPT_FOLDER_ROOT/.wwscripts/"
	# Uses `md5sum` separately in order to avoid masking a return value, as Shellcheck recommends
	INFO_MD5SUM=$(md5sum <<< "$FILTERBY$FILTERALT") || exit 1
	# Ensures that the script file exists
	SCRIPT_NAME=$(head -c 32 <<< "$INFO_MD5SUM") || exit 1
	SCRIPT_PATH="$SCRIPT_FOLDER$SCRIPT_NAME"
	ensure_script "$FILTERBY" "$FILTERALT" "$TOGGLE"

	SCRIPT_NAME="ww$RANDOM"

	INFO_DBUS_SEND=$(dbus_kwin /Scripting org.kde.kwin.Scripting.loadScript "string:$SCRIPT_PATH" "string:$SCRIPT_NAME") || exit 1
	# Uses `awk` separately in order to avoid masking a return value, as Shellcheck recommends
	ID=$(awk '{print $2}' <<< "$INFO_DBUS_SEND") || exit 1

	# Use kwin version to decide how to call the script run api which changes between kwin versions.
	# See https://github.com/academo/ww-run-raise/issues/15#issuecomment-2632214974 for more info.
	kwinVersion=$(get_kwin_version)

	if ver_between 5.21.90 "$kwinVersion" 5.27.79; then
		SCRIPT_API_PATH=org.kde.kwin.Script
		SCRIPT_PATH="/$ID"
	elif ver_lt 5.27.80 "$kwinVersion"; then
		SCRIPT_API_PATH=org.kde.kwin.Script
		SCRIPT_PATH="/Scripting/Script$ID"
	else
		SCRIPT_API_PATH=org.kde.kwin.Scripting
		SCRIPT_PATH="/$ID"
	fi

	# Run using detected pat
	dbus_kwin "$SCRIPT_PATH" ${SCRIPT_API_PATH}.run >/dev/null 2>&1

	# Stop using same path
	dbus_kwin "$SCRIPT_PATH" ${SCRIPT_API_PATH}.stop >/dev/null 2>&1

elif [[ -n "$COMMAND" ]]; then
	$COMMAND &
fi
