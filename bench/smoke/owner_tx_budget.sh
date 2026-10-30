#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-tx-budget.XXXXXX")
DB="$WORK/db"
ENDPOINT="$DB/MYLSM.sock"
OWNER_PID=

cleanup() {
  status=$?
  if [[ -n "$OWNER_PID" ]] && kill -0 "$OWNER_PID" 2>/dev/null; then
    kill -TERM "$OWNER_PID" 2>/dev/null || true
    wait "$OWNER_PID" 2>/dev/null || true
  fi
  if [[ "$status" -ne 0 ]]; then
    cat "$WORK/setup.log" "$WORK/owner.log" >&2 2>/dev/null || true
  fi
  rm -rf -- "$WORK"
}

trap cleanup EXIT HUP INT TERM

bend "$ROOT/bench/smoke/owner_frame_limit_setup.bend" -o "$WORK/setup"
bend "$ROOT/app/owner/mylsm_owner.bend" -o "$WORK/owner"
MYLSM_DB_PATH="$DB" MYLSM_SESSION_MODE=create "$WORK/setup" >"$WORK/setup.log"

options() {
  python3 - "$@" <<'PY'
import struct
import sys
response = int(sys.argv[1])
frame = response
receive = int(sys.argv[5]) if len(sys.argv) > 5 else max(frame, 3 * frame + 48)
queue_requests = int(sys.argv[2]) if len(sys.argv) > 2 else 8
queue_bytes = int(sys.argv[3]) if len(sys.argv) > 3 else 1048576
queue_timeout = int(sys.argv[4]) if len(sys.argv) > 4 else 30000
fields = [64, frame, receive, response, 120000, 120000,
          queue_requests, queue_bytes, queue_timeout, 64, 4096, 64, 67108864, 64,
          16384, 65536, 67108864]
print((b"MLO6" + struct.pack(">I", 1) + struct.pack(">17I", *fields)).hex())
PY
}

start_owner() {
  MYLSM_DB_PATH="$DB" "$WORK/owner" --resource-options-v1 "$(options "$@")" >"$WORK/owner.log" 2>&1 &
  OWNER_PID=$!
  for _ in $(seq 1 100); do
    if [[ -S "$ENDPOINT" ]] && kill -0 "$OWNER_PID" 2>/dev/null; then
      if python3 - "$ENDPOINT" <<'PY'
import socket
import sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect(sys.argv[1])
except OSError:
    raise SystemExit(1)
s.close()
PY
      then
        return
      fi
    fi
    if ! kill -0 "$OWNER_PID" 2>/dev/null; then
      cat "$WORK/owner.log" >&2
      exit 1
    fi
    sleep 0.05
  done
  cat "$WORK/owner.log" >&2
  exit 1
}

stop_owner() {
  kill -TERM "$OWNER_PID" 2>/dev/null || true
  wait "$OWNER_PID" 2>/dev/null || true
  OWNER_PID=
}

start_owner 512
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" seed
stop_owner
start_owner 128
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" impossible
stop_owner
start_owner 512
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" reopen
stop_owner
start_owner 512
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" operation_matrix
stop_owner

start_owner 35651584 2 67108864 300000
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" seed_large
stop_owner
start_owner 128
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" cursor_impossible
stop_owner
start_owner 35651584 2 67108864 300000
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" fifo
stop_owner
start_owner 35651584 2 67108864 300000
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" reopen_fifo
stop_owner

start_owner 35651584 1 67108864 250
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" timeout
stop_owner
start_owner 35651584 8 1048576 30000
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" commit_once
stop_owner
start_owner 35651584 8 1048576 30000
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" reopen_final
stop_owner
start_owner 512
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" post_matrix
stop_owner
start_owner 512
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" reopen_post_matrix
stop_owner

DB="$WORK/cdb"
ENDPOINT="$DB/MYLSM.sock"
MYLSM_DB_PATH="$DB" MYLSM_SESSION_MODE=create "$WORK/setup" >"$WORK/cursor-setup.log"
start_owner 512
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" seed_cursor_root
stop_owner
start_owner 128
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" cursor_exact
stop_owner

DB="$WORK/rdb"
ENDPOINT="$DB/MYLSM.sock"
MYLSM_DB_PATH="$DB" MYLSM_SESSION_MODE=create "$WORK/setup" >"$WORK/race-setup.log"
start_owner 4194304 8 16777216
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" seed_cursor_race
stop_owner
start_owner 4194304 8 16777216
python3 "$ROOT/bench/smoke/owner_tx_budget.py" "$ENDPOINT" cursor_race
stop_owner

printf '%s\n' OWNER_TX_BUDGET_PASSED
