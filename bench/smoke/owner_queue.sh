#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-queue.XXXXXX")
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
OPTIONS_OVERSIZED=$(python3 - <<'PY'
import struct
fields = [64, 16777216, 16777216, 16777216, 30000, 30000, 2, 63, 30000,
          64, 4096, 64, 67108864, 64, 16384, 65536, 67108864]
print((b"MLO6" + struct.pack(">I", 1) + struct.pack(">17I", *fields)).hex())
PY
)
OPTIONS_CANCEL=$(python3 - <<'PY'
import struct
fields = [64, 16777216, 16777216, 16777216, 30000, 30000, 2, 128, 30000,
          64, 4096, 64, 67108864, 64, 16384, 65536, 67108864]
print((b"MLO6" + struct.pack(">I", 1) + struct.pack(">17I", *fields)).hex())
PY
)
start_owner() {
  MYLSM_DB_PATH="$DB" "$WORK/owner" --resource-options-v1 "$1" >"$WORK/owner.log" 2>&1 &
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

start_owner "$OPTIONS_OVERSIZED"
python3 "$ROOT/bench/smoke/owner_queue.py" "$ENDPOINT" reject
stop_owner
start_owner "$OPTIONS_CANCEL"
python3 "$ROOT/bench/smoke/owner_queue.py" "$ENDPOINT" cancel "$OWNER_PID"
stop_owner
start_owner "$OPTIONS_OVERSIZED"
python3 "$ROOT/bench/smoke/owner_queue.py" "$ENDPOINT" reopen
stop_owner
printf '%s\n' OWNER_QUEUE_PASSED
