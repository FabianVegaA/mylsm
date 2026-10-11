#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-backup-crash.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
BINARY="$WORK/backup-worker"
SOURCE="$ROOT/bench/smoke/public_backup_file.bend"

case $(uname -s) in
  Darwin|Linux) ;;
  *) exit 2 ;;
esac

bend "$SOURCE" -o "$BINARY"

run_case() {
  local checkpoint=$1
  local database="$WORK/$checkpoint/db"
  local backup="$WORK/$checkpoint/backup"
  local log="$WORK/$checkpoint.log"
  local pid

  mkdir -p "$(dirname -- "$database")"
  MYLSM_DB_PATH="$database" \
  MYLSM_BACKUP_PATH="$backup" \
  MYLSM_CRASH_POINT="$checkpoint" \
    "$BINARY" >"$log" 2>&1 &
  pid=$!

  for attempt in {1..200}; do
    if grep -qxF "crash_point_reached=$checkpoint" "$log"; then
      break
    fi
    kill -0 "$pid"
    sleep 0.05
  done
  grep -qxF "crash_point_reached=$checkpoint" "$log"
  kill -KILL "$pid"
  wait "$pid" 2>/dev/null || true

  case "$checkpoint" in
    backup.before_rename)
      test ! -e "$backup"
      test -f "$backup.backup-060.tmp/BACKUP"
      ;;
    backup.renamed|backup.parent_synced)
      test -f "$backup/BACKUP"
      ;;
  esac
}

run_case backup.before_rename
run_case backup.renamed
run_case backup.parent_synced
printf '%s\n' 'BACKUP_PUBLISH_CRASH_PASS'
