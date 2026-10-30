#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-reactor-write.XXXXXX")
DB="$WORK/db"
ENDPOINT="$DB/MYLSM.sock"
OWNER_PID=

cleanup() {
  status=$?
  if [[ -n "$OWNER_PID" ]] && kill -0 "$OWNER_PID" 2>/dev/null; then
    kill "$OWNER_PID" 2>/dev/null || true
    wait "$OWNER_PID" 2>/dev/null || true
  fi
  if [[ "$status" -ne 0 ]]; then
    cat "$WORK/setup.log" "$WORK/owner.log" >&2 2>/dev/null || true
  fi
  rm -rf -- "$WORK"
}

trap cleanup EXIT HUP INT TERM

bend "$ROOT/bench/smoke/owner_reactor_write_backpressure.bend" -o "$WORK/setup"
bend "$ROOT/app/owner/mylsm_owner.bend" -o "$WORK/owner"
MYLSM_DB_PATH="$DB" MYLSM_SESSION_MODE=create "$WORK/setup" >"$WORK/setup.log"
MYLSM_DB_PATH="$DB" "$WORK/owner" >"$WORK/owner.log" 2>&1 &
OWNER_PID=$!

ready=0
for _ in $(seq 1 100); do
  if [[ -S "$ENDPOINT" ]]; then
    ready=1
    break
  fi
  if ! kill -0 "$OWNER_PID" 2>/dev/null; then
    cat "$WORK/owner.log" >&2
    exit 1
  fi
  sleep 0.05
done

if [[ "$ready" -ne 1 ]]; then
  cat "$WORK/owner.log" >&2
  exit 1
fi

python3 "$ROOT/bench/smoke/owner_reactor_write_backpressure.py" "$ENDPOINT"
kill -0 "$OWNER_PID"
printf '%s\n' 'OWNER_REACTOR_WRITE_BACKPRESSURE_PASSED'
