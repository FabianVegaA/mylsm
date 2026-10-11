#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-backup-file.XXXXXX")
trap 'chmod u+w "$WORK/readonly" 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkdir "$WORK/readonly"
chmod 500 "$WORK/readonly"

MYLSM_DB_PATH="$WORK/db" \
MYLSM_BACKUP_PATH="$WORK/backup" \
MYLSM_BACKUP_BLOCKED_PATH="$WORK/readonly/backup" \
  bend "$ROOT/bench/smoke/public_backup_file.bend"

test -d "$WORK/backup"
test -f "$WORK/backup/BACKUP"
test "$(wc -c < "$WORK/backup/BACKUP" | tr -d ' ')" -gt 131072
test ! -e "$WORK/backup.backup-060.tmp"

MYLSM_BACKUP_PATH="$WORK/backup" \
MYLSM_RESTORE_DESTINATION="$WORK/restored" \
MYLSM_RESTORE_CHECK_PATH="$WORK/restored" \
  bend "$ROOT/bench/smoke/public_restore_from.bend"

MYLSM_DB_PATH="$WORK/delta-db" \
MYLSM_BACKUP_PATH="$WORK/delta-backup" \
MYLSM_BACKUP_BLOCKED_PATH="$WORK/readonly/delta-backup" \
MYLSM_BACKUP_SKIP_FLUSH=true \
  bend "$ROOT/bench/smoke/public_backup_file.bend"

test -f "$WORK/delta-backup/BACKUP"
test "$(wc -c < "$WORK/delta-backup/BACKUP" | tr -d ' ')" -gt 131072

MYLSM_BACKUP_PATH="$WORK/delta-backup" \
MYLSM_RESTORE_DESTINATION="$WORK/delta-restored" \
MYLSM_RESTORE_CHECK_PATH="$WORK/delta-restored" \
  bend "$ROOT/bench/smoke/public_restore_from.bend"
