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

BASE_PATH=/mnt/inom

read -p "Sync files!"

rcp --delete $BASE_PATH/.ssh $HOME/
rcp --delete $BASE_PATH/Wiki $HOME/
rcp --delete $BASE_PATH/Life/ $HOME/Documents/Personal
rcp --delete $BASE_PATH/.secrets/password-store/ ~/.password-store/
