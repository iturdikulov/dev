#!/usr/bin/env bash

# An rsync that respects gitignore
rcp() {
    #   -a = -rlptgoD
    #   -r = recursive
    #   -l = copy symlinks as symlinks
    #   -p = preserve permissions
    #   -t = preserve mtimes
    #   -g = preserve owning group
    #   -o = preserve owner
    # -z = use compression
    # -P = show progress on transferred file
    # -J = don't touch mtimes on symlinks (always errors)
    rsync -rtzPJ \
        --include=.git/ \
        "$@"
}

VIRTIO_NAME=inom
VIRTIO_PATH=/mnt
BASE_PATH="$VIRTIO_PATH/$VIRTIO_NAME"

sudo mount -t virtiofs "$VIRTIO_NAME" "$VIRTIO_PATH" || echo "Already mounted"

read -p "Sync files!"

rcp --delete $BASE_PATH/.ssh $HOME/
rcp --delete $BASE_PATH/Wiki $HOME/
rcp --delete $BASE_PATH/Life/ $HOME/Documents/Personal
rcp --delete $BASE_PATH/.secrets/password-store/ ~/.password-store/

FIREFOX_PROFILES="$HOME/.mozilla/firefox"
FIREFOX_PROFILE_PATH="$FIREFOX_PROFILES/inom.default"

mkdir -p "$FIREFOX_PROFILE_PATH"
cat > "$FIREFOX_PROFILES/profiles.ini" << EOF
[Profile0]
Name=default-esr
IsRelative=1
Path=inom.default
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

FIREFOX_PROFILE_SRC="$BASE_PATH/.mozilla/firefox/inom.default"
cd "$FIREFOX_PROFILE_SRC" || {
    echo "Failed to change directory to $FIREFOX_PROFILE_SRC"
    exit 1
}
for i in $(cat <<EOF
cookies.sqlite
handlers.json
prefs.js
containers.json
places.sqlite
permissions.sqlite
webappsstore.sqlite
storage.sqlite
cert9.db
EOF
); do rcp "$FIREFOX_PROFILE_SRC/$i" "$FIREFOX_PROFILE_PATH"; done

firefox -p
