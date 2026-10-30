#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-restore-crash.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
RESTORE="$WORK/restore-worker"
REOPEN="$WORK/reopen-worker"

case $(uname -s) in
  Darwin|Linux) ;;
  *) exit 2 ;;
esac

bend "$ROOT/bench/smoke/public_restore_io.bend" -o "$RESTORE"
bend "$ROOT/bench/crash/restore_reopen.bend" -o "$REOPEN"

run_case() {
  local checkpoint=$1
  local case_dir="$WORK/$checkpoint"
  local destination="$case_dir/database"
  local invalid="$case_dir/invalid"
  local temporary="$case_dir/temp"
  local staging="$destination.restore-060.tmp"
  local log="$case_dir.log"
  local pid status socket

  mkdir -p "$case_dir"
  mkdir "$temporary.restore-060.tmp"
  MYLSM_RESTORE_DESTINATION="$destination" \
  MYLSM_RESTORE_INVALID_DESTINATION="$invalid" \
  MYLSM_RESTORE_TEMP_DESTINATION="$temporary" \
  MYLSM_CRASH_POINT="$checkpoint" \
    "$RESTORE" >"$log" 2>&1 &
  pid=$!

  for attempt in {1..200}; do
    if grep -qxF "crash_point_reached=$checkpoint" "$log"; then
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      cat "$log"
      return 1
    fi
    sleep 0.05
  done
  grep -qxF "crash_point_reached=$checkpoint" "$log"
  kill -KILL "$pid"
  set +e
  wait "$pid" 2>/dev/null
  status=$?
  set -e
  [[ "$status" -eq 137 ]]

  case "$checkpoint" in
    restore.before_rename)
      [[ ! -e "$destination" ]]
      [[ -d "$staging" ]]
      ;;
    restore.renamed|restore.parent_synced)
      [[ -d "$destination" ]]
      [[ ! -e "$staging" ]]
      MYLSM_DB_PATH="$destination" "$REOPEN" | grep -qxF 'RESTORE_REOPEN_PASSED'
      ;;
  esac
}

run_case restore.before_rename
run_case restore.renamed
run_case restore.parent_synced
printf '%s\n' 'RESTORE_PUBLISH_CRASH_PASS'
