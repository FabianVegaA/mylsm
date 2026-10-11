#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-commit-unknown.XXXXXX")
DB="$WORK/db"
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

MYLSM_DB_PATH="$DB" MYLSM_CRASH_POINT=owner.after_mutation.before_response \
  "$WORK/owner" >"$WORK/owner.log" 2>&1 &
OWNER_PID=$!

for ((attempt = 0; attempt < 500; attempt += 1)); do
  if [[ -S "$DB/MYLSM.sock" ]]; then
    break
  fi
  if ! kill -0 "$OWNER_PID" 2>/dev/null; then
    cat "$WORK/owner.log"
    exit 1
  fi
  sleep 0.02
done
[[ -S "$DB/MYLSM.sock" ]] || { cat "$WORK/owner.log"; exit 1; }

MYLSM_DB_PATH="$DB" MYLSM_CRASH_TEST_MODE=client \
  "$WORK/client" >"$WORK/client.log" 2>&1 &
CLIENT_PID=$!

for ((attempt = 0; attempt < 500; attempt += 1)); do
  if grep -qxF 'crash_point_reached=owner.after_mutation.before_response' \
      "$WORK/owner.log"; then
    break
  fi
  if ! kill -0 "$OWNER_PID" 2>/dev/null; then
    cat "$WORK/owner.log"
    exit 1
  fi
  sleep 0.02
done
grep -qxF 'crash_point_reached=owner.after_mutation.before_response' \
  "$WORK/owner.log"

kill -9 "$OWNER_PID"
set +e
wait "$OWNER_PID"
OWNER_STATUS=$?
set -e
OWNER_PID=
[[ "$OWNER_STATUS" -eq 137 ]] || { echo "owner kill status was $OWNER_STATUS" >&2; exit 1; }

wait "$CLIENT_PID"
CLIENT_PID=
grep -qxF 'COMMIT_UNKNOWN_RECEIVED' "$WORK/client.log"
rm -f -- "$DB/MYLSM.sock"

MYLSM_DB_PATH="$DB" MYLSM_CRASH_TEST_MODE=verify "$WORK/client" >"$WORK/verify.log" 2>&1
grep -qxF 'COMMITTED_VALUE_RECOVERED' "$WORK/verify.log"
echo 'OWNER_COMMIT_UNKNOWN_RECOVERY_PASSED'
