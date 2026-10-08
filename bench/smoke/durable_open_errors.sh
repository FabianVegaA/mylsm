#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build/durable-open-errors"
BINARY="$BUILD_DIR/durable_open_errors"
SOURCE="$ROOT/bench/smoke/durable_open_errors.bend"

mkdir -p -- "$BUILD_DIR"
if [[ -n ${MYLSM_BEND_CC:-} ]]; then
  CC="$MYLSM_BEND_CC" bend "$SOURCE" -o "$BINARY"
else
  bend "$SOURCE" -o "$BINARY"
fi

run_case() {
  local kind=$1 manifest=$2 path="$BUILD_DIR/$1-db" before="$BUILD_DIR/$1-before" after="$BUILD_DIR/$1-after"
  rm -rf -- "$path"
  mkdir -p -- "$path"
  printf '%b' "$manifest" > "$path/MANIFEST"
  cp -p "$path/MANIFEST" "$before"
  printf '%s\n' 'keep-this-file' > "$path/orphan.tmp"
  cp -p "$path/orphan.tmp" "$before.tmp"
  MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=open MYLSM_EXPECTED_ERROR="$kind" "$BINARY" > "$BUILD_DIR/$kind.log"
  grep -qx "OPEN_ERROR_$kind" "$BUILD_DIR/$kind.log"
  cp -p "$path/MANIFEST" "$after"
  cmp -s "$before" "$after"
  cmp -s "$before.tmp" "$path/orphan.tmp"
  test ! -e "$path/LOCK"
  test ! -e "$path/wal.log"
}

run_case unsupported '\x4d\x59\x4c\x53\x4d\x33\x4d\x00\x00\x00\x00\x04'
run_case corrupt 'not-a-manifest'

path="$BUILD_DIR/valid-0.4-db"
rm -rf -- "$path"
mkdir -p -- "$path"
printf '%s' '4d594c534d334d0000000003000000001205c80e921bb2ce3c951dca55299a11f60403d7440d7f3949c06848ca9fd22a' | xxd -r -p > "$path/MANIFEST"
MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=open MYLSM_EXPECTED_ERROR=valid_0_4 "$BINARY" > "$BUILD_DIR/valid-0.4.log"
grep -qx OPEN_VALID "$BUILD_DIR/valid-0.4.log"
test -f "$path/wal.log"

path="$BUILD_DIR/corrupt-sst-db"
rm -rf -- "$path"
MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=seed_sst MYLSM_EXPECTED_ERROR=missing "$BINARY" > "$BUILD_DIR/corrupt-sst-seed.log"
grep -qx OPEN_SST_SEEDED "$BUILD_DIR/corrupt-sst-seed.log"
table=$(find "$path/l0" -type f -print -quit)
test -n "$table"
printf '%s\n' 'corrupt-table' > "$table"
MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=open MYLSM_EXPECTED_ERROR=corrupt "$BINARY" > "$BUILD_DIR/corrupt-sst.log"
grep -qx OPEN_ERROR_corrupt "$BUILD_DIR/corrupt-sst.log"

path="$BUILD_DIR/corrupt-wal-db"
rm -rf -- "$path"
MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=seed_sst MYLSM_EXPECTED_ERROR=missing "$BINARY" > "$BUILD_DIR/corrupt-wal-seed.log"
grep -qx OPEN_SST_SEEDED "$BUILD_DIR/corrupt-wal-seed.log"
printf '%s\n' 'corrupt-wal' > "$path/wal.log"
MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=open MYLSM_EXPECTED_ERROR=corrupt "$BINARY" > "$BUILD_DIR/corrupt-wal.log"
grep -qx OPEN_ERROR_corrupt "$BUILD_DIR/corrupt-wal.log"

path="$BUILD_DIR/wal-open-io-db"
rm -rf -- "$path"
MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=seed_sst MYLSM_EXPECTED_ERROR=missing "$BINARY" > "$BUILD_DIR/wal-open-io-seed.log"
grep -qx OPEN_SST_SEEDED "$BUILD_DIR/wal-open-io-seed.log"
rm -- "$path/wal.log"
mkdir -- "$path/wal.log"
MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=open MYLSM_EXPECTED_ERROR=io "$BINARY" > "$BUILD_DIR/wal-open-io.log"
grep -qx OPEN_ERROR_io "$BUILD_DIR/wal-open-io.log"
test -d "$path/wal.log"

path="$BUILD_DIR/recovery-sweep-io-db"
rm -rf -- "$path"
MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=seed_sst MYLSM_EXPECTED_ERROR=missing "$BINARY" > "$BUILD_DIR/recovery-sweep-seed.log"
mkdir -p -- "$path/l0/stuck.tmp"
printf '%s\n' 'preserve-child' > "$path/l0/stuck.tmp/child"
cp -p "$path/MANIFEST" "$BUILD_DIR/recovery-sweep-manifest-before"
MYLSM_DB_PATH="$path" MYLSM_OPEN_MODE=open MYLSM_EXPECTED_ERROR=io "$BINARY" > "$BUILD_DIR/recovery-sweep-io.log"
grep -qx OPEN_ERROR_io "$BUILD_DIR/recovery-sweep-io.log"
cmp -s "$BUILD_DIR/recovery-sweep-manifest-before" "$path/MANIFEST"
test -f "$path/l0/stuck.tmp/child"

printf '%s\n' 'DURABLE OPEN ERRORS PASS'
