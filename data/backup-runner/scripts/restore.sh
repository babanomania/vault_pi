#!/bin/bash
# Restore a borg archive to /restore inside the container. The host can
# then `docker cp backup-runner:/restore/snapshot/. vw-data/` to put data
# back. We deliberately don't write directly to /data — the live volume
# might still be in use by vaultwarden.
#
# Usage:
#   docker compose run --rm backup-runner restore                # latest
#   docker compose run --rm backup-runner restore <archive-name> # named
#   docker compose run --rm backup-runner list                   # which archives exist

set -eo pipefail

archive="${1:-latest}"
if [ "$archive" = "latest" ]; then
  archive=$(borg list --last 1 --format '{archive}{NL}' "${BORG_REPO}")
fi
if [ -z "$archive" ]; then
  echo "No archive found." >&2
  exit 1
fi

rm -rf /restore
mkdir -p /restore
cd /restore
echo "==> Extracting ${archive} -> /restore"
borg extract -v "${BORG_REPO}::${archive}"

echo
echo "==> Done. Contents:"
ls -la /restore/snapshot/
echo
echo "Next steps on the host:"
echo "  docker compose stop vaultwarden"
echo "  docker cp backup-runner:/restore/snapshot/. /home/pi/containers/vw-data/"
echo "  sudo chown -R \$USER:\$USER /home/pi/containers/vw-data"
echo "  docker compose start vaultwarden"
