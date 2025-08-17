#!/bin/sh

# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }

export BORG_REPO="$1"
# # Verify paths exist
# if [ ! -d "$BORG_REPO" ]; then
#     info "One or more backup paths do not exist, exiting. Check $BORG_REPO and $BORG_ROOT_BACKUP_PATH"
#     exit 1
# fi

# # Verify sendmail and borg aviability
# if command -v sendmail >/dev/null 2>&1 && command -v borg >/dev/null 2>&1; then
#         info "Sendmail and Borg are available."
#     else
#         info "Sendmail and/or Borg are not available, exiting."
#         exit 1
#     fi

# Verify root access
if [ "$(id -u)" -ne 0 ]; then
    info "Root access is required for this script."
    exit 1
fi

trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

info "Starting backup"

# Backup the most important directories into an archive named after
# the machine this script is currently running on:

borg create \
    --verbose \
    --filter AME \
    --list \
    --stats \
    --show-rc \
    --compression zstd,1 \
    --exclude-caches \
    --exclude "home/*/.cache/*" \
    --exclude "home/*/.npm" \
    --exclude "home/*/.steam" \
    --exclude "home/*/Media/" \
    --exclude "home/*/.thunderbird/*/calendar-data/cache.sqlite*" \
    --exclude "var/tmp/*" \
    --exclude "var/log/*" \
    --exclude "var/cache/*" \
    --exclude "*/Cache" \
    --exclude ".config/Slack/logs" \
    --exclude ".container-diff" \
    --exclude "*/node_modules" \
    --exclude "*/_build" \
    --exclude "*/.tox" \
    --exclude "*/venv" \
    --exclude "*/.venv" \
    \
    ::'{hostname}-{now}' \
    "/etc" \
    "/home" \
    "/root" \
    "/var"

backup_exit=$?

info "Pruning repository"

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-*' matching is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

borg prune                          \
    --list                          \
    --glob-archives '{hostname}-*'  \
    --show-rc                       \
    --keep-daily    7               \
    --keep-weekly   4               \
    --keep-monthly  6

prune_exit=$?

# actually free repo disk space by compacting segments

info "Compacting repository"

borg compact

compact_exit=$?

# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

if [ ${global_exit} -eq 0 ]; then
    info "Backup, Prune, and Compact finished successfully"

   # # TODO remove /README postfix to sync all repo
   # ${pkgs.rclone}/bin/rclone sync -v --config ${config.user.home}/.config/rclone/rclone.conf \
   # --bwlimit 2M  --max-duration 9h \
   # /archive/backup/file/${name} repo:${name}
   #
   # # TODO weekly borg and rsync verify script
   # ls -l /archive/backup/file/${name}
elif [ ${global_exit} -eq 1 ]; then
    info "Backup, Prune, and/or Compact finished with warnings"
    su - inom -c 'printf "To: inom@iturdikulov.com\nSubject: Backup warnings at %s\n\n%s\n" "$(date)" "$(systemctl status --full borgbackup.service)" | msmtp -a default inom@iturdikulov.com'
else
    info "Backup, Prune, and/or Compact finished with errors"
    su - inom -c 'printf "To: inom@iturdikulov.com\nSubject: Backup failed at %s\n\n%s\n" "$(date)" "$(systemctl status --full borgbackup.service)" | msmtp -a default inom@iturdikulov.com'
fi

exit ${global_exit}
