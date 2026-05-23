#!/bin/bash
# Create a consistent point-in-time backup of vw-data into the borg repo.
#
# SQLite considerations: vaultwarden is writing to /data/db.sqlite3 in WAL
# mode while we're running. Borg-creating the raw file would capture a
# torn snapshot. SQLite's online backup API (`.backup`) gives us an
# atomic, consistent copy without coordinating with vaultwarden.
#
# All other files in vw-data (rsa keys, attachments, sends, icon_cache)
# are append-only or atomic-rename, so plain copies are fine.

set -eo pipefail
. /scripts/notify.sh
trap 'notify "❌ backup FAILED at $(date -u +%Y-%m-%dT%H:%M:%SZ)"; rm -rf /snapshot' ERR

start=$(date +%s)
echo "==> backup-runner starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Initialise the repo on first run.
if [ ! -f "${BORG_REPO}/config" ]; then
  echo "==> Initialising borg repo at ${BORG_REPO} (repokey-blake2)"
  borg init --encryption=repokey-blake2 "${BORG_REPO}"
fi

# 1. Consistent point-in-time copy of the SQLite DB.
rm -rf /snapshot
mkdir -p /snapshot
echo "==> Snapshotting db.sqlite3 via SQLite online backup API"
sqlite3 /data/db.sqlite3 ".backup '/snapshot/db.sqlite3'"

# 2. Static files (atomic replace by vaultwarden, safe to plain-copy).
echo "==> Copying rsa keys + attachments + sends + icon_cache"
for f in rsa_key.pem rsa_key.pub.pem config.json; do
  [ -f "/data/$f" ] && cp -a "/data/$f" "/snapshot/$f"
done
for d in attachments sends icon_cache tmp; do
  if [ -d "/data/$d" ]; then
    mkdir -p "/snapshot/$d"
    cp -a "/data/$d/." "/snapshot/$d/" 2>/dev/null || true
  fi
done

# 3. Borg archive.
archive="vaultwarden-{now:%Y-%m-%dT%H:%M:%S}"
echo "==> Creating borg archive ${archive}"
borg create -v --stats \
  --compression=zstd,3 \
  "${BORG_REPO}::${archive}" \
  /snapshot

# 4. Prune old archives. Keep 7 daily, 4 weekly, 3 monthly.
echo "==> Pruning archives (keep 7 daily / 4 weekly / 3 monthly)"
borg prune -v --list "${BORG_REPO}" \
  --glob-archives='vaultwarden-*' \
  --keep-daily=7 \
  --keep-weekly=4 \
  --keep-monthly=3

# 5. Compact (1.2+) reclaims disk space freed by prune.
echo "==> Compacting repo"
borg compact "${BORG_REPO}" || true

rm -rf /snapshot
elapsed=$(( $(date +%s) - start ))
notify "✅ backup complete in ${elapsed}s ($(du -sh "${BORG_REPO}" 2>/dev/null | awk '{print $1}'))"
