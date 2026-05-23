#!/bin/bash
# Inverse of sync.sh — pulls the borg repo back from the cloud remote into
# the local borg_repo volume. Use when restoring onto a fresh Pi where the
# local repo is empty / lost.

set -eo pipefail
. /scripts/notify.sh
trap 'notify "❌ sync-restore FAILED at $(date -u +%Y-%m-%dT%H:%M:%SZ)"' ERR

src_path="${REMOTE_PATH:-${DROPBOX_PATH:-vaultwarden_backups}}"
start=$(date +%s)

echo "==> Pulling remote:${src_path} -> ${BORG_REPO}"
rclone -v \
  --transfers=2 --checkers=2 \
  sync "remote:${src_path}" "${BORG_REPO}"

elapsed=$(( $(date +%s) - start ))
notify "✅ sync-restore from remote:${src_path} complete in ${elapsed}s"

echo
echo "Repo restored locally. Next: ./entrypoint.sh restore [archive]"
