#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-lifecycle.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
OWNER="$WORK/owner"
CREATE="$WORK/create"

case $(uname -s) in
  Darwin|Linux) ;;
  *) exit 2 ;;
esac

bend "$ROOT/app/owner/mylsm_owner.bend" -o "$OWNER"
bend "$ROOT/bench/smoke/owner_generation_create.bend" -o "$CREATE"

generation_hex() {
  od -An -tx1 "$1/OWNER.GEN" | tr -d ' \n'
}

wait_checkpoint() {
  local pid="$1"
  local log="$2"
  local checkpoint="$3"
  for attempt in {1..200}; do
    if grep -qxF "crash_point_reached=$checkpoint" "$log"; then
      return
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      cat "$log"
      return 1
    fi
    sleep 0.05
  done
  cat "$log"
  return 1
}

run_case() {
  local checkpoint="$1"
  local expected_after_restart="$2"
  local db="$WORK/$checkpoint/db"
  local log="$WORK/$checkpoint.log"
  local restart_log="$WORK/$checkpoint-restart.log"
  local pid restart_pid status old_socket_id=

  mkdir -p "$(dirname "$db")"
  MYLSM_DB_PATH="$db" "$CREATE" >/dev/null
  MYLSM_DB_PATH="$db" MYLSM_CRASH_POINT="$checkpoint" \
    "$OWNER" >"$log" 2>&1 &
  pid=$!
  wait_checkpoint "$pid" "$log" "$checkpoint"
  case "$checkpoint" in
    owner.after_lock)
      [[ ! -e "$db/OWNER.GEN" ]]
      [[ ! -e "$db/MYLSM.sock" ]]
      ;;
    owner.after_generation)
      [[ "$(generation_hex "$db")" == "00000001" ]]
      [[ ! -e "$db/MYLSM.sock" ]]
      ;;
    owner.endpoint_published)
      [[ "$(generation_hex "$db")" == "00000001" ]]
      [[ -S "$db/MYLSM.sock" ]]
      old_socket_id=$(ls -di "$db/MYLSM.sock" | awk '{print $1}')
      ;;
  esac
  kill -KILL "$pid"
  set +e
  wait "$pid" 2>/dev/null
  status=$?
  set -e
  [[ "$status" -eq 137 ]]

  MYLSM_DB_PATH="$db" "$OWNER" >"$restart_log" 2>&1 &
  restart_pid=$!
  for attempt in {1..200}; do
    if [[ -S "$db/MYLSM.sock" &&
      "$(generation_hex "$db")" == "$expected_after_restart" ]]; then
      break
    fi
    if ! kill -0 "$restart_pid" 2>/dev/null; then
      cat "$restart_log"
      return 1
    fi
    sleep 0.05
  done
  [[ -S "$db/MYLSM.sock" ]]
  [[ "$(generation_hex "$db")" == "$expected_after_restart" ]]
  if [[ -n "$old_socket_id" ]]; then
    [[ "$(ls -di "$db/MYLSM.sock" | awk '{print $1}')" != "$old_socket_id" ]]
  fi
  kill -KILL "$restart_pid"
  wait "$restart_pid" 2>/dev/null || true
}

run_case owner.after_lock 00000001
run_case owner.after_generation 00000002
run_case owner.endpoint_published 00000002
printf '%s\n' 'OWNER_ENDPOINT_LIFECYCLE_PASS'
