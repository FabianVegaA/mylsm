#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-generation.XXXXXX")
DB="$WORK/db"
OWNER_PID=
trap 'if [[ -n "$OWNER_PID" ]]; then kill "$OWNER_PID" 2>/dev/null || true; wait "$OWNER_PID" 2>/dev/null || true; fi; rm -rf "$WORK"' EXIT

bend "$ROOT/bench/smoke/owner_generation_create.bend" -o "$WORK/create"
bend "$ROOT/bench/smoke/owner_generation_client.bend" -o "$WORK/client"
bend "$ROOT/bench/smoke/owner_generation_stale.bend" -o "$WORK/stale-client"
bend "$ROOT/app/owner/mylsm_owner.bend" -o "$WORK/owner"
MYLSM_DB_PATH="$DB" "$WORK/create"

start_owner() {
  local expected_generation="$1"
  local previous_socket_id="$2"
  local current_generation=
  local current_socket_id=
  MYLSM_DB_PATH="$DB" "$WORK/owner" >"$WORK/owner.log" 2>&1 &
  OWNER_PID=$!
  for ((attempt = 0; attempt < 500; attempt += 1)); do
    if [[ -S "$DB/MYLSM.sock" ]]; then
      current_generation=$(generation_hex)
      current_socket_id=$(ls -di "$DB/MYLSM.sock" 2>/dev/null | awk '{print $1}')
      if [[ "$current_generation" == "$expected_generation" &&
        "$current_socket_id" != "$previous_socket_id" ]]; then
        return
      fi
    fi
    if ! kill -0 "$OWNER_PID" 2>/dev/null; then
      cat "$WORK/owner.log"
      exit 1
    fi
    sleep 0.02
  done
  cat "$WORK/owner.log"
  exit 1
}

generation_hex() {
  od -An -tx1 "$DB/OWNER.GEN" | tr -d ' \n'
}

stop_owner() {
  kill -TERM "$OWNER_PID"
  wait "$OWNER_PID" 2>/dev/null || true
  OWNER_PID=
}

start_owner "00000001" ""
[[ "$(generation_hex)" == "00000001" ]]
MYLSM_DB_PATH="$DB" "$WORK/client"
stop_owner

old_socket_id=$(ls -di "$DB/MYLSM.sock" | awk '{print $1}')
start_owner "00000002" "$old_socket_id"
[[ "$(generation_hex)" == "00000002" ]]
MYLSM_OWNER_ENDPOINT="$DB/MYLSM.sock" "$WORK/stale-client"
MYLSM_DB_PATH="$DB" "$WORK/client"
stop_owner
printf '%s\n' OWNER_GENERATION_RESTART_PASSED
bash "$ROOT/bench/smoke/owner_generation_tokens.sh"
