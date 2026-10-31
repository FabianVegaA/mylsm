#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-socket.XXXXXX")
DB="$WORK/db"
BUDGET_DB="$WORK/budget-db"
SERVER_PID=
CLIENT_ONE_PID=
CLIENT_TWO_PID=
OWNER_BACKUP_PID=
trap 'for pid in "$CLIENT_ONE_PID" "$CLIENT_TWO_PID" "$OWNER_BACKUP_PID" "$SERVER_PID"; do if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; done; rm -rf "$WORK"' EXIT

bend "$ROOT/bench/smoke/coordinator_owner_socket.bend" -o "$WORK/owner-server"
bend "$ROOT/bench/smoke/coordinator_owner_client.bend" -o "$WORK/owner-client"
bend "$ROOT/bench/smoke/public_coordinator_client.bend" -o "$WORK/public-owner-client"
bend "$ROOT/bench/smoke/public_utf8_coordinator_client.bend" -o "$WORK/public-utf8-owner-client"
bend "$ROOT/bench/smoke/public_live_scan.bend" -o "$WORK/public-live-scan"
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
MYLSM_DB_PATH="$DB" "$WORK/public-live-scan"
MYLSM_DB_PATH="$DB" "$WORK/public-utf8-owner-client"
MYLSM_DB_PATH="$DB" MYLSM_OWNER_ACTION=backup \
MYLSM_BACKUP_PATH="$WORK/owner-backup" "$WORK/public-owner-client" &
OWNER_BACKUP_PID=$!
wait "$OWNER_BACKUP_PID"
OWNER_BACKUP_PID=
kill -TERM "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=
rm -f -- "$DB/MYLSM.sock"
MYLSM_BACKUP_PATH="$WORK/owner-backup" \
MYLSM_RESTORE_DESTINATION="$WORK/owner-restored" \
MYLSM_RESTORE_CHECK_PATH="$WORK/owner-restored" \
  bend "$ROOT/bench/smoke/public_owner_backup_restore.bend"
MYLSM_DB_PATH="$DB" "$WORK/owner-reacquire"
MYLSM_DB_PATH="$BUDGET_DB" MYLSM_OWNER_FUEL=1 "$WORK/owner-server" >"$WORK/budget.log" 2>&1 &
SERVER_PID=$!
for ((attempt = 0; attempt < 500; attempt += 1)); do
  if [[ -S "$BUDGET_DB/MYLSM.sock" ]]; then
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    cat "$WORK/budget.log"
    exit 1
  fi
  sleep 0.02
done
[[ -S "$BUDGET_DB/MYLSM.sock" ]]
MYLSM_OWNER_ENDPOINT="$BUDGET_DB/MYLSM.sock" "$WORK/owner-client" >/dev/null 2>&1 || true
wait "$SERVER_PID"
SERVER_PID=
grep -qx OWNER_STOPPED "$WORK/budget.log"
if [[ -S "$BUDGET_DB/MYLSM.sock" ]]; then
  exit 1
fi
MYLSM_DB_PATH="$BUDGET_DB" "$WORK/owner-reacquire"
