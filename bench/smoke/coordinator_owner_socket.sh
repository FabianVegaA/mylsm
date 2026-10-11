#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-socket.XXXXXX")
DB="$WORK/db"
SERVER_PID=
trap 'if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; fi; rm -rf "$WORK"' EXIT

bend "$ROOT/bench/smoke/coordinator_owner_socket.bend" -o "$WORK/owner-server"
bend "$ROOT/bench/smoke/coordinator_owner_client.bend" -o "$WORK/owner-client"
MYLSM_DB_PATH="$DB" "$WORK/owner-server" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!

for ((attempt = 0; attempt < 500; attempt += 1)); do
  if [[ -S "$DB/OWNER.sock" ]]; then
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    cat "$WORK/server.log"
    exit 1
  fi
  sleep 0.02
done

if [[ ! -S "$DB/OWNER.sock" ]]; then
  cat "$WORK/server.log"
  exit 1
fi

MYLSM_OWNER_ENDPOINT="$DB/OWNER.sock" "$WORK/owner-client"
wait "$SERVER_PID"
SERVER_PID=
cat "$WORK/server.log"
if [[ -S "$DB/OWNER.sock" ]]; then
  exit 1
fi
