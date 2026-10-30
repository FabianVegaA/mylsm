#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-options.XXXXXX")
DB="$WORK/db"
OWNER_PID=
OPTIONS_HEX=4d4c4f36000000010000004001000000010000000100000000007530000075300000004001000000000075300000002000001000000000400400000000000040000040000001000004000000
trap 'if [[ -n "$OWNER_PID" ]]; then kill "$OWNER_PID" 2>/dev/null || true; wait "$OWNER_PID" 2>/dev/null || true; fi; rm -rf "$WORK"' EXIT

bend "$ROOT/bench/smoke/owner_generation_create.bend" -o "$WORK/create"
bend "$ROOT/bench/smoke/owner_options_client.bend" -o "$WORK/client"
bend "$ROOT/app/owner/mylsm_owner.bend" -o "$WORK/owner"
MYLSM_DB_PATH="$DB" "$WORK/create"

MYLSM_DB_PATH="$DB" MYLSM_OPTIONS_MODE=absent "$WORK/client"
[[ ! -S "$DB/MYLSM.sock" ]]
[[ ! -e "$DB/OWNER.GEN" ]]

if MYLSM_DB_PATH="$DB" "$WORK/owner" --resource-options-v1 invalid >"$WORK/invalid.log" 2>&1; then
  cat "$WORK/invalid.log"
  exit 1
else
  status=$?
fi
[[ "$status" -eq 2 ]]
[[ ! -S "$DB/MYLSM.sock" ]]
[[ ! -e "$DB/OWNER.GEN" ]]

MYLSM_DB_PATH="$DB" "$WORK/owner" --resource-options-v1 "$OPTIONS_HEX" >"$WORK/owner.log" 2>&1 &
OWNER_PID=$!
for ((attempt = 0; attempt < 500; attempt += 1)); do
  if [[ -S "$DB/MYLSM.sock" && -f "$DB/OWNER.GEN" ]]; then
    break
  fi
  if ! kill -0 "$OWNER_PID" 2>/dev/null; then
    cat "$WORK/owner.log"
    exit 1
  fi
  sleep 0.02
done
[[ -S "$DB/MYLSM.sock" ]]
MYLSM_DB_PATH="$DB" MYLSM_OPTIONS_MODE=owner "$WORK/client"
kill "$OWNER_PID"
wait "$OWNER_PID" 2>/dev/null || true
OWNER_PID=
printf '%s\n' OWNER_OPTIONS_PASSED
