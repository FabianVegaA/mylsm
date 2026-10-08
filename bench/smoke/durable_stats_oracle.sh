#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build/durable-stats-oracle"
BINARY="$BUILD_DIR/durable_stats_oracle"
DB="$BUILD_DIR/db"
mkdir -p -- "$BUILD_DIR"
if [[ -n ${MYLSM_BEND_CC:-} ]]; then
  CC="$MYLSM_BEND_CC" bend "$ROOT/bench/smoke/durable_stats_oracle.bend" -o "$BINARY"
else
  bend "$ROOT/bench/smoke/durable_stats_oracle.bend" -o "$BINARY"
fi
rm -rf -- "$DB"
MYLSM_DB_PATH="$DB" "$BINARY" > "$BUILD_DIR/run.log"
grep -qx ACTIVE_BYTES_EXACT "$BUILD_DIR/run.log"
grep -qx STATS_ORACLE_CLOSED "$BUILD_DIR/run.log"
printf '%s\n' 'DURABLE STATS ORACLE PASS'
