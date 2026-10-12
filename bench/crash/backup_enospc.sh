#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-backup-enospc.XXXXXX")
ENOSPC_DIR=${MYLSM_ENOSPC_DIR:?set MYLSM_ENOSPC_DIR to a mounted, size-limited filesystem}
RESERVE="$ENOSPC_DIR/mylsm-reserve-$$"
DESTINATION="$ENOSPC_DIR/mylsm-backup-$$"
trap 'rm -f -- "$RESERVE"; rm -rf -- "$WORK"' EXIT HUP INT TERM

case $(uname -s) in
  Linux) ;;
  *) exit 2 ;;
esac

test -d "$ENOSPC_DIR"
DATABASE="$WORK/database"
MYLSM_BACKUP_LIMIT_MODE=create MYLSM_DB_PATH="$DATABASE" \
  MYLSM_BACKUP_PATH="$DESTINATION" \
  bend "$ROOT/bench/smoke/backup_file_limit.bend" >"$WORK/create.log"
grep -qxF BACKUP_LIMIT_SOURCE_READY "$WORK/create.log"
BEFORE=$(find "$DATABASE" -type f -exec cksum {} \; | sort)

fallocate -l 63k "$RESERVE"
AVAILABLE=$(df -B1 --output=avail "$ENOSPC_DIR" | tail -1 | tr -d ' ')
test "$AVAILABLE" = 0

MYLSM_BACKUP_LIMIT_MODE=backup MYLSM_DB_PATH="$DATABASE" \
  MYLSM_BACKUP_PATH="$DESTINATION" \
  bend "$ROOT/bench/smoke/backup_file_limit.bend" >"$WORK/backup.log" 2>&1
grep -qxF BACKUP_FILE_LIMIT_HANDLED "$WORK/backup.log"
test ! -e "$DESTINATION"
test ! -e "$DESTINATION.backup-060.tmp"
test "$BEFORE" = "$(find "$DATABASE" -type f -exec cksum {} \; | sort)"
printf '%s\n' BACKUP_ENOSPC_CLEANUP_PASSED
