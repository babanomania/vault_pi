#!/bin/bash
# Dispatcher for the vault_pi backup-runner. Called by `docker compose run
# --rm backup-runner <command>`. Defaults to `backup`.
set -eo pipefail

cmd="${1:-backup}"
shift || true

case "$cmd" in
  backup)        exec /scripts/backup.sh "$@" ;;
  sync)          exec /scripts/sync.sh "$@" ;;
  restore)       exec /scripts/restore.sh "$@" ;;
  sync-restore)  exec /scripts/sync_restore.sh "$@" ;;
  list)          exec borg list "$BORG_REPO" ;;
  info)          exec borg info "$BORG_REPO" "$@" ;;
  shell)         exec bash ;;
  *)
    cat >&2 <<EOF
Unknown command: $cmd

Usage: docker compose run --rm backup-runner <command>

  backup           snapshot vw-data + create new borg archive
  sync             rclone-sync the borg repo to the configured remote
  restore [ARCH]   extract ARCH (default: latest) to /restore inside container
  sync-restore     pull the remote borg repo back into local storage
  list             list archives in the local borg repo
  info             show borg repo / archive info
  shell            drop into bash for ad-hoc debugging
EOF
    exit 1
    ;;
esac
