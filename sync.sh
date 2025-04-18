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

rcp --delete /mnt/.ssh $HOME/
rcp --delete /mnt/Wiki $HOME/
rcp --delete /mnt/Videos $HOME/
rcp --delete /mnt/Life/ $HOME/Documents/Personal
