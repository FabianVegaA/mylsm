#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-backup-file-limit.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT HUP INT TERM
DATABASE="$WORK/database"
DESTINATION="$WORK/backup"

case $(uname -s) in
  Darwin|Linux) ;;
  *) exit 2 ;;
esac

MYLSM_BACKUP_LIMIT_MODE=create MYLSM_DB_PATH="$DATABASE" \
  MYLSM_BACKUP_PATH="$DESTINATION" \
  bend "$ROOT/bench/smoke/backup_file_limit.bend" >"$WORK/create.log"
grep -qxF BACKUP_LIMIT_SOURCE_READY "$WORK/create.log"

(
  ulimit -c 0
  ulimit -f 0
  trap '' XFSZ
  MYLSM_BACKUP_LIMIT_MODE=backup MYLSM_DB_PATH="$DATABASE" \
    MYLSM_BACKUP_PATH="$DESTINATION" \
    bend "$ROOT/bench/smoke/backup_file_limit.bend"
) 2>&1 | cat >"$WORK/backup.log"

grep -qxF BACKUP_FILE_LIMIT_HANDLED "$WORK/backup.log"
test ! -e "$DESTINATION"
test ! -e "$DESTINATION.backup-060.tmp"
printf '%s\n' BACKUP_FILE_LIMIT_PASSED
