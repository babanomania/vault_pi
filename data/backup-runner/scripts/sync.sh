#!/bin/bash
# rclone-sync the local borg repo to the configured cloud remote.
# rclone reads its config from /run/secrets/rclone.conf (RCLONE_CONFIG env).

set -eo pipefail
. /scripts/notify.sh
trap 'notify "❌ sync FAILED at $(date -u +%Y-%m-%dT%H:%M:%SZ)"' ERR

dest_path="${REMOTE_PATH:-${DROPBOX_PATH:-vaultwarden_backups}}"
start=$(date +%s)

echo "==> Syncing ${BORG_REPO} -> remote:${dest_path}"
# --transfers / --checkers tuned conservatively for Pi Zero 2W RAM.
rclone -v \
  --transfers=2 --checkers=2 \
  --bwlimit-file=8M \
  sync "${BORG_REPO}" "remote:${dest_path}"

elapsed=$(( $(date +%s) - start ))
notify "✅ sync to remote:${dest_path} complete in ${elapsed}s"
