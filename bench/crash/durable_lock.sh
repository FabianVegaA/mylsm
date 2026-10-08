#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build/durable-lock"
WORK="$BUILD_DIR/data"
BINARY="$BUILD_DIR/db_lock"
SOURCE="$ROOT/bench/smoke/db_lock.bend"

case $(uname -s) in
  Darwin|Linux) ;;
  *) exit 2 ;;
esac

rm -rf -- "$BUILD_DIR"
mkdir -p -- "$WORK/db"
bend "$SOURCE" -o "$BINARY"
printf 'stable-data\n' > "$WORK/db/payload"
cp "$WORK/db/payload" "$WORK/payload.expected"
ln -s "$WORK/db" "$WORK/alias"

MYLSM_LOCK_PATH="$WORK/db" MYLSM_LOCK_MODE=same-process "$BINARY" > "$BUILD_DIR/same-process.log"
grep -q '^LOCK_BUSY$' "$BUILD_DIR/same-process.log"

MYLSM_LOCK_PATH="$WORK/db" MYLSM_LOCK_MODE=hold "$BINARY" > "$BUILD_DIR/owner.log" 2>&1 &
OWNER=$!
for attempt in {1..100}; do
  if grep -q '^LOCK_ACQUIRED$' "$BUILD_DIR/owner.log"; then
    break
  fi
  kill -0 "$OWNER"
  sleep 0.05
done
grep -q '^LOCK_ACQUIRED$' "$BUILD_DIR/owner.log"

for alias in "$WORK/db/../db" "$WORK/alias"; do
  if MYLSM_LOCK_PATH="$alias" MYLSM_LOCK_MODE=busy "$BINARY" > "$BUILD_DIR/contender.log" 2>&1; then
    grep -q '^LOCK_BUSY$' "$BUILD_DIR/contender.log"
  else
    cat "$BUILD_DIR/contender.log" >&2
    exit 1
  fi
done
cmp -s "$WORK/db/payload" "$WORK/payload.expected"
wait "$OWNER"
grep -q '^LOCK_RELEASED$' "$BUILD_DIR/owner.log"
MYLSM_LOCK_PATH="$WORK/db" MYLSM_LOCK_MODE=once "$BINARY" > "$BUILD_DIR/closed-owner-reopen.log"
grep -q '^LOCK_ACQUIRED$' "$BUILD_DIR/closed-owner-reopen.log"
grep -q '^LOCK_RELEASED$' "$BUILD_DIR/closed-owner-reopen.log"

MYLSM_LOCK_PATH="$WORK/db" MYLSM_LOCK_MODE=hold "$BINARY" > "$BUILD_DIR/killed-owner.log" 2>&1 &
OWNER=$!
for attempt in {1..100}; do
  if grep -q '^LOCK_ACQUIRED$' "$BUILD_DIR/killed-owner.log"; then
    break
  fi
  kill -0 "$OWNER"
  sleep 0.05
done
grep -q '^LOCK_ACQUIRED$' "$BUILD_DIR/killed-owner.log"
kill -KILL "$OWNER"
wait "$OWNER" 2>/dev/null || true
MYLSM_LOCK_PATH="$WORK/db" MYLSM_LOCK_MODE=once "$BINARY" > "$BUILD_DIR/reopened.log"
grep -q '^LOCK_ACQUIRED$' "$BUILD_DIR/reopened.log"
grep -q '^LOCK_RELEASED$' "$BUILD_DIR/reopened.log"
cmp -s "$WORK/db/payload" "$WORK/payload.expected"
printf '%s\n' 'DURABLE LOCK PASS'
