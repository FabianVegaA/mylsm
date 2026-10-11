#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-socket.XXXXXX")
DB="$WORK/db"
SERVER_PID=
CLIENT_ONE_PID=
CLIENT_TWO_PID=
trap 'for pid in "$CLIENT_ONE_PID" "$CLIENT_TWO_PID" "$SERVER_PID"; do if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; done; rm -rf "$WORK"' EXIT

bend "$ROOT/bench/smoke/coordinator_owner_socket.bend" -o "$WORK/owner-server"
bend "$ROOT/bench/smoke/coordinator_owner_client.bend" -o "$WORK/owner-client"
bend "$ROOT/bench/smoke/public_coordinator_client.bend" -o "$WORK/public-owner-client"
bend "$ROOT/bench/smoke/public_utf8_coordinator_client.bend" -o "$WORK/public-utf8-owner-client"
bend "$ROOT/bench/smoke/coordinator_owner_reacquire.bend" -o "$WORK/owner-reacquire"
MYLSM_DB_PATH="$DB" "$WORK/owner-server" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!

for ((attempt = 0; attempt < 500; attempt += 1)); do
  if [[ -S "$DB/MYLSM.sock" ]]; then
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    cat "$WORK/server.log"
    exit 1
  fi
  sleep 0.02
done

if [[ ! -S "$DB/MYLSM.sock" ]]; then
  cat "$WORK/server.log"
  exit 1
fi

printf '\000\000\000\001' > "$DB/OWNER.GEN"

MYLSM_OWNER_ENDPOINT="$DB/MYLSM.sock" "$WORK/owner-client" &
CLIENT_ONE_PID=$!
MYLSM_OWNER_ENDPOINT="$DB/MYLSM.sock" "$WORK/owner-client" &
CLIENT_TWO_PID=$!
wait "$CLIENT_ONE_PID"
CLIENT_ONE_PID=
wait "$CLIENT_TWO_PID"
CLIENT_TWO_PID=
MYLSM_DB_PATH="$DB" "$WORK/public-owner-client"
MYLSM_DB_PATH="$DB" "$WORK/public-utf8-owner-client"
wait "$SERVER_PID"
SERVER_PID=
cat "$WORK/server.log"
if [[ -S "$DB/MYLSM.sock" ]]; then
  exit 1
fi
MYLSM_DB_PATH="$DB" "$WORK/owner-reacquire"
