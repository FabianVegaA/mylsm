#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d /private/tmp/mst.XXXXXX)
DB="$WORK/db"
INITIAL_PID=
OWNER_PID=

cleanup() {
  local result=$?
  for pid in "$INITIAL_PID" "$OWNER_PID"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf -- "$WORK"
  exit "$result"
}
trap cleanup EXIT

bend "$ROOT/bench/smoke/coordinator_owner_socket.bend" -o "$WORK/initial-owner"
bend "$ROOT/app/owner/mylsm_owner.bend" -o "$WORK/owner"
bend "$ROOT/bench/smoke/coordinator_owner_client.bend" -o "$WORK/client"
bend "$ROOT/bench/smoke/coordinator_owner_reacquire.bend" -o "$WORK/reacquire"

MYLSM_DB_PATH="$DB" "$WORK/initial-owner" >"$WORK/initial.log" 2>&1 &
INITIAL_PID=$!
for ((attempt = 0; attempt < 500; attempt += 1)); do
  [[ -S "$DB/MYLSM.sock" ]] && break
  if ! kill -0 "$INITIAL_PID" 2>/dev/null; then
    cat "$WORK/initial.log"
    exit 1
  fi
  sleep 0.02
done
[[ -S "$DB/MYLSM.sock" ]] || { cat "$WORK/initial.log"; exit 1; }

kill -9 "$INITIAL_PID"
set +e
wait "$INITIAL_PID"
initial_status=$?
set -e
INITIAL_PID=
[[ "$initial_status" -eq 137 ]] || { echo "initial owner kill status was $initial_status" >&2; exit 1; }
[[ -S "$DB/MYLSM.sock" ]] || { echo "owner kill did not leave a stale endpoint" >&2; exit 1; }

MYLSM_DB_PATH="$DB" "$WORK/owner" >"$WORK/owner.log" 2>&1 &
OWNER_PID=$!
client_ready=0
for ((attempt = 0; attempt < 500; attempt += 1)); do
  if MYLSM_OWNER_ENDPOINT="$DB/MYLSM.sock" "$WORK/client" \
      >"$WORK/client.log" 2>&1; then
    client_ready=1
    break
  fi
  if ! kill -0 "$OWNER_PID" 2>/dev/null; then
    cat "$WORK/owner.log"
    cat "$WORK/client.log"
    exit 1
  fi
  sleep 0.02
done
[[ "$client_ready" -eq 1 ]] || {
  cat "$WORK/owner.log"
  cat "$WORK/client.log"
  exit 1
}
grep -qxF 'OWNER_CLIENT_DISCONNECTED' "$WORK/client.log"

kill -9 "$OWNER_PID"
set +e
wait "$OWNER_PID"
owner_status=$?
set -e
OWNER_PID=
[[ "$owner_status" -eq 137 ]] || { echo "restarted owner kill status was $owner_status" >&2; exit 1; }
MYLSM_DB_PATH="$DB" "$WORK/reacquire"
echo 'STALE_OWNER_ENDPOINT_RECOVERED'
