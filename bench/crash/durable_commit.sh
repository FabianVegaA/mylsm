#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build/durable-commit"
BINARY="$BUILD_DIR/durable_commit"
SOURCE="$ROOT/bench/crash/durable_commit.bend"

mkdir -p -- "$BUILD_DIR"
if [[ -n ${MYLSM_BEND_CC:-} ]]; then
  CC="$MYLSM_BEND_CC" bend "$SOURCE" -o "$BINARY"
else
  bend "$SOURCE" -o "$BINARY"
fi

run_seed() {
  MYLSM_DB_PATH="$1" MYLSM_DURABLE_MODE=seed "$BINARY" > "$BUILD_DIR/seed.log"
}

run_crash() {
  local path=$1 mode=$2 checkpoint=$3 log=$4 pid
  MYLSM_DB_PATH="$path" MYLSM_DURABLE_MODE="$mode" MYLSM_CRASH_POINT="$checkpoint" "$BINARY" > "$log" 2>&1 &
  pid=$!
  for attempt in {1..200}; do
    if grep -q "^crash_point_reached=$checkpoint$" "$log"; then
      kill -KILL "$pid"
      wait "$pid" 2>/dev/null || true
      return
    fi
    kill -0 "$pid"
    sleep 0.05
  done
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  cat "$log" >&2
  return 1
}

inspect() {
  MYLSM_DB_PATH="$1" MYLSM_DURABLE_MODE=inspect "$BINARY" > "$2"
}

run_wal_case() {
  local checkpoint=$1 expected=$2 path="$BUILD_DIR/$1-db" log="$BUILD_DIR/$1.log" result="$BUILD_DIR/$1-result.log"
  rm -rf -- "$path"
  run_seed "$path"
  run_crash "$path" wal "$checkpoint" "$log"
  inspect "$path" "$result"
  if [[ $expected == either ]]; then
    grep -Eq '^RECOVERED_(old|new)$' "$result"
  else
    grep -qx "RECOVERED_$expected" "$result"
  fi
  grep -qx CLOSED "$result"
}

run_wal_case wal.before_append old
run_wal_case wal.appended either
run_wal_case wal.synced new

path="$BUILD_DIR/flush-db"
rm -rf -- "$path"
run_seed "$path"
run_crash "$path" flush flush.table_synced "$BUILD_DIR/flush.log"
inspect "$path" "$BUILD_DIR/flush-result.log"
grep -qx RECOVERED_new "$BUILD_DIR/flush-result.log"
grep -qx CLOSED "$BUILD_DIR/flush-result.log"

path="$BUILD_DIR/maintenance-db"
if [[ -d "$path/l0" ]]; then
  chmod 755 "$path/l0"
fi
rm -rf -- "$path"
run_seed "$path"
mkdir -p -- "$path/l0"
chmod 555 "$path/l0"
restore_maintenance_dir() {
  chmod 755 "$path/l0" 2>/dev/null || true
}
trap restore_maintenance_dir EXIT
MYLSM_DB_PATH="$path" MYLSM_DURABLE_MODE=maintenance "$BINARY" > "$BUILD_DIR/maintenance.log"
chmod 755 "$path/l0"
trap - EXIT
grep -qx MAINTENANCE_FAILED "$BUILD_DIR/maintenance.log"
grep -qx MAINTENANCE_READABLE "$BUILD_DIR/maintenance.log"
grep -qx MAINTENANCE_BLOCKED "$BUILD_DIR/maintenance.log"
grep -qx CLOSED "$BUILD_DIR/maintenance.log"

printf '%s\n' 'DURABLE COMMIT PASS'
