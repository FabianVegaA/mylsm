#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build/durable-open-wait"
BINARY="$BUILD_DIR/open_wait"
DB="$BUILD_DIR/db"
ALIAS="$BUILD_DIR/db-alias"
SOURCE="$ROOT/bench/smoke/open_wait.bend"

mkdir -p -- "$BUILD_DIR"
rm -rf -- "$DB" "$ALIAS"
bend "$SOURCE" -o "$BINARY"
MYLSM_WAIT_MODE=create MYLSM_WAIT_PATH="$DB" "$BINARY" > "$BUILD_DIR/create.log"
ln -s "$DB" "$ALIAS"

MYLSM_WAIT_MODE=hold MYLSM_WAIT_PATH="$DB" "$BINARY" > "$BUILD_DIR/owner.log" 2>&1 &
OWNER=$!
for attempt in {1..100}; do
  if grep -q '^OWNER_LOCKED$' "$BUILD_DIR/owner.log"; then
    break
  fi
  kill -0 "$OWNER"
  sleep 0.01
done
grep -q '^OWNER_LOCKED$' "$BUILD_DIR/owner.log"

MYLSM_WAIT_MODE=timeout MYLSM_WAIT_PATH="$ALIAS" "$BINARY" > "$BUILD_DIR/timeout.log"
grep -qx OPEN_TIMED_OUT "$BUILD_DIR/timeout.log"
wait "$OWNER"
grep -q '^OWNER_RELEASED$' "$BUILD_DIR/owner.log"

MYLSM_WAIT_MODE=wait MYLSM_WAIT_PATH="$ALIAS" "$BINARY" > "$BUILD_DIR/wait.log"
grep -qx OPEN_ACQUIRED "$BUILD_DIR/wait.log"
printf '%s\n' 'DURABLE OPEN WAIT PASS'
