#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-migration-crash.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
MIGRATE="$WORK/migrate-worker"
REOPEN="$WORK/reopen-worker"

case $(uname -s) in
  Darwin|Linux) ;;
  *) exit 2 ;;
esac

bend "$ROOT/bench/smoke/legacy_migrate.bend" -o "$MIGRATE"
bend "$ROOT/bench/crash/migration_reopen.bend" -o "$REOPEN"

run_case() {
  local checkpoint=$1
  local database="$WORK/$checkpoint/source"
  local destination="$WORK/$checkpoint/destination"
  local log="$WORK/$checkpoint.log"
  local before pid

  mkdir -p "$database"
  MYLSM_DB_PATH="$database" bend "$ROOT/bench/smoke/legacy_sst_io.bend" >/dev/null
  before=$(find "$database" -type f -exec cksum {} \; | sort)

  MYLSM_DB_PATH="$database" \
  MYLSM_MIGRATE_DEST="$destination" \
  MYLSM_CRASH_POINT="$checkpoint" \
    "$MIGRATE" >"$log" 2>&1 &
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

  test "$before" = "$(find "$database" -type f -exec cksum {} \; | sort)"
  case "$checkpoint" in
    backup.before_rename)
      test ! -e "$destination"
      test -f "$destination.migrate-060.bundle.backup-060.tmp/BACKUP"
      ;;
    backup.renamed|backup.parent_synced)
      test ! -e "$destination"
      test -f "$destination.migrate-060.bundle/BACKUP"
      ;;
    restore.before_rename)
      test ! -e "$destination"
      test -d "$destination.restore-060.tmp"
      test -f "$destination.migrate-060.bundle/BACKUP"
      ;;
    restore.renamed|restore.parent_synced)
      test -d "$destination"
      test ! -e "$destination.restore-060.tmp"
      MYLSM_DB_PATH="$destination" "$REOPEN" | grep -qxF 'MIGRATION_REOPEN_PASSED'
      ;;
  esac
}

run_case backup.before_rename
run_case backup.renamed
run_case backup.parent_synced
run_case restore.before_rename
run_case restore.renamed
run_case restore.parent_synced
printf '%s\n' 'MIGRATION_PUBLISH_CRASH_PASS'
