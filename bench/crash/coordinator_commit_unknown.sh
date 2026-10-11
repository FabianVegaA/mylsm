#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d /private/tmp/mcu.XXXXXX)
OWNER_PID=
CLIENT_PID=

cleanup() {
  local status=$?
  for pid in "$CLIENT_PID" "$OWNER_PID"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf -- "$WORK"
  exit "$status"
}
trap cleanup EXIT

bend "$ROOT/bench/smoke/coordinator_owner_socket.bend" -o "$WORK/owner"
bend "$ROOT/bench/crash/coordinator_commit_unknown.bend" -o "$WORK/client"

run_case() {
  local checkpoint=$1 expected_present=$2 case_dir db owner_log client_log verify_log marker
  case_dir="$WORK/$checkpoint"
  db="$case_dir/db"
  owner_log="$case_dir/owner.log"
  client_log="$case_dir/client.log"
  verify_log="$case_dir/verify.log"
  marker="crash_point_reached=$checkpoint"
  mkdir -p -- "$case_dir"

  MYLSM_DB_PATH="$db" MYLSM_CRASH_POINT="$checkpoint" \
    "$WORK/owner" >"$owner_log" 2>&1 &
  OWNER_PID=$!

  for ((attempt = 0; attempt < 500; attempt += 1)); do
    if [[ -S "$db/MYLSM.sock" ]]; then
      break
    fi
    if ! kill -0 "$OWNER_PID" 2>/dev/null; then
      cat "$owner_log"
      return 1
    fi
    sleep 0.02
  done
  [[ -S "$db/MYLSM.sock" ]] || { cat "$owner_log"; return 1; }

  MYLSM_DB_PATH="$db" MYLSM_CRASH_TEST_MODE=client \
    "$WORK/client" >"$client_log" 2>&1 &
  CLIENT_PID=$!

  for ((attempt = 0; attempt < 500; attempt += 1)); do
    if grep -qxF "$marker" "$owner_log"; then
      break
    fi
    if ! kill -0 "$OWNER_PID" 2>/dev/null; then
      cat "$owner_log"
      return 1
    fi
    sleep 0.02
  done
  grep -qxF "$marker" "$owner_log"

  kill -9 "$OWNER_PID"
  set +e
  wait "$OWNER_PID"
  owner_status=$?
  set -e
  OWNER_PID=
  [[ "$owner_status" -eq 137 ]] || {
    echo "owner kill status was $owner_status at $checkpoint" >&2
    return 1
  }

  wait "$CLIENT_PID"
  CLIENT_PID=
  grep -qxF 'COMMIT_UNKNOWN_RECEIVED' "$client_log"
  rm -f -- "$db/MYLSM.sock"

  expected=no
  [[ "$expected_present" == present ]] && expected=yes
  MYLSM_DB_PATH="$db" MYLSM_CRASH_TEST_MODE=verify \
    MYLSM_EXPECT_PRESENT="$expected" "$WORK/client" >"$verify_log" 2>&1
  if [[ "$expected_present" == present ]]; then
    grep -qxF 'COMMITTED_VALUE_RECOVERED' "$verify_log"
  else
    grep -qxF 'UNCOMMITTED_VALUE_ABSENT' "$verify_log"
  fi
  echo "OWNER_CRASH_BOUNDARY_PASSED checkpoint=$checkpoint recovered=$expected_present"
}

run_case wal.before_append absent
run_case wal.during_append absent
run_case wal.after_sync_before_apply present
run_case owner.after_apply present
run_case owner.before_response present
run_case owner.after_mutation.before_response present
echo 'OWNER_COMMIT_UNKNOWN_RECOVERY_PASSED'
