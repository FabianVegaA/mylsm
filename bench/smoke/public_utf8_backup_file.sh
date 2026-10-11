#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-utf8-backup-file.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

MYLSM_DB_PATH="$WORK/db" \
MYLSM_BACKUP_PATH="$WORK/backup" \
  bend "$ROOT/bench/smoke/public_utf8_backup_file.bend"

test -f "$WORK/backup/BACKUP"
