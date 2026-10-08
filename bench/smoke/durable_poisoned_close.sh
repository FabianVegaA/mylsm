#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build/durable-poisoned-close"
BINARY="$BUILD_DIR/durable_poisoned_close"
SOURCE="$ROOT/bench/smoke/durable_poisoned_close.bend"
DB="$BUILD_DIR/db"

mkdir -p -- "$BUILD_DIR"
if [[ -n ${MYLSM_BEND_CC:-} ]]; then
  CC="$MYLSM_BEND_CC" bend "$SOURCE" -o "$BINARY"
else
  bend "$SOURCE" -o "$BINARY"
fi

rm -rf -- "$DB"
MYLSM_DB_PATH="$DB" MYLSM_POISON_MODE=seed "$BINARY" > "$BUILD_DIR/seed.log"
grep -qx SEEDED "$BUILD_DIR/seed.log"
cp -p "$DB/wal.log" "$BUILD_DIR/wal.saved"
MYLSM_DB_PATH="$DB" MYLSM_POISON_MODE=poison MYLSM_CRASH_POINT=wal.appended "$BINARY" > "$BUILD_DIR/poison.log" 2>&1 &
PID=$!
for attempt in {1..200}; do
  if grep -qx 'crash_point_reached=wal.appended' "$BUILD_DIR/poison.log"; then
    break
  fi
  kill -0 "$PID"
  sleep 0.05
done
grep -qx 'crash_point_reached=wal.appended' "$BUILD_DIR/poison.log"
kill -0 "$PID"
rm -- "$DB/wal.log"
kill -CONT "$PID"
wait "$PID"
grep -qx POISON_READY "$BUILD_DIR/poison.log"
grep -qx POISONED "$BUILD_DIR/poison.log"
grep -qx POISONED_CLOSED "$BUILD_DIR/poison.log"
mv -- "$BUILD_DIR/wal.saved" "$DB/wal.log"
MYLSM_DB_PATH="$DB" MYLSM_POISON_MODE=reopen "$BINARY" > "$BUILD_DIR/reopen.log"
grep -qx RECOVERED "$BUILD_DIR/reopen.log"
grep -qx REOPEN_CLOSED "$BUILD_DIR/reopen.log"

printf '%s\n' 'DURABLE POISONED CLOSE PASS'
