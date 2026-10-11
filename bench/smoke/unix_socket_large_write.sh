#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d /tmp/mylsm-unix-socket-large.XXXXXX)
DB="$WORK/db"
mkdir "$DB"
SERVER_PID=
trap 'if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; fi; rm -rf "$WORK"' EXIT

bend "$ROOT/bench/smoke/unix_socket_large_write.bend" -o "$WORK/server"
bend "$ROOT/bench/smoke/unix_socket_large_write_client.bend" -o "$WORK/client"
MYLSM_DB_PATH="$DB" "$WORK/server" >"$WORK/server.log" 2>&1 &
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

MYLSM_DB_PATH="$DB" "$WORK/client"
wait "$SERVER_PID"
SERVER_PID=
cat "$WORK/server.log"
