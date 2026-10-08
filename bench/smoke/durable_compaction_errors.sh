#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build/durable-compaction-errors"
BINARY="$BUILD_DIR/durable_compaction_errors"
DB="$BUILD_DIR/db"
mkdir -p -- "$BUILD_DIR"
if [[ -n ${MYLSM_BEND_CC:-} ]]; then
  CC="$MYLSM_BEND_CC" bend "$ROOT/bench/smoke/durable_compaction_errors.bend" -o "$BINARY"
else
  bend "$ROOT/bench/smoke/durable_compaction_errors.bend" -o "$BINARY"
fi
rm -rf -- "$DB"
MYLSM_DB_PATH="$DB" MYLSM_COMPACTION_MODE=seed "$BINARY" > "$BUILD_DIR/seed.log"
printf '%s\n' 'occupied' > "$DB/l1"
MYLSM_DB_PATH="$DB" MYLSM_COMPACTION_MODE=compact "$BINARY" > "$BUILD_DIR/compact.log"
grep -qx COMPACTION_IO_RETURNED "$BUILD_DIR/compact.log"
grep -qx DB_CLOSED "$BUILD_DIR/compact.log"
rm -f -- "$DB/l1"
MYLSM_DB_PATH="$DB" MYLSM_COMPACTION_MODE=verify "$BINARY" > "$BUILD_DIR/verify.log"
grep -qx COMPACTION_DATA_READABLE "$BUILD_DIR/verify.log"
printf '%s\n' 'DURABLE COMPACTION ERRORS PASS'
