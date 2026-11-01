#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-retired-sst.XXXXXX")
trap 'rm -rf -- "$DB"' EXIT
rmdir -- "$DB"

MYLSM_DB_PATH="$DB" MYLSM_BYTES_MODE=create bend "$ROOT/bench/smoke/public_bytes_api.bend" >/dev/null
test -e "$DB/SST.00000001"
test -e "$DB/SST.00000002"
printf 'partial' > "$DB/SST.00000003.tmp"
printf 'keep' > "$DB/notes.txt"
mkdir -- "$DB/SST.00000009"
MYLSM_DB_PATH="$DB" MYLSM_BYTES_MODE=open bend "$ROOT/bench/smoke/public_bytes_api.bend" >/dev/null
test ! -e "$DB/SST.00000001"
test ! -e "$DB/SST.00000003.tmp"
test -s "$DB/SST.00000002"
test -e "$DB/notes.txt"
test -d "$DB/SST.00000009"
DAMAGED="$DB-damaged"
trap 'rm -rf -- "$DB" "$DAMAGED"' EXIT
MYLSM_DB_PATH="$DAMAGED" MYLSM_BYTES_MODE=create bend "$ROOT/bench/smoke/public_bytes_api.bend" >/dev/null
printf 'damaged' > "$DAMAGED/SST.00000002"
if MYLSM_DB_PATH="$DAMAGED" MYLSM_BYTES_MODE=open bend "$ROOT/bench/smoke/public_bytes_api.bend" >/dev/null 2>&1; then
  printf '%s\n' 'opening a damaged database unexpectedly succeeded' >&2
  exit 1
fi
test -s "$DAMAGED/SST.00000001"
printf '%s\n' 'BYTE RETIRED SST RECLAIM PASS'
