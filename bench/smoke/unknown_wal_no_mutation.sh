#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-unknown-format.XXXXXX")
trap 'rm -rf "$DB"' EXIT
rmdir "$DB"

MYLSM_DB_PATH="$DB" MYLSM_BYTES_MODE=create bend "$ROOT/bench/smoke/public_bytes_api.bend"
printf 'UNKNOWN!' | dd of="$DB/WAL" bs=8 count=1 conv=notrunc status=none
cp "$DB/WAL" "$DB/WAL.expected"
if MYLSM_DB_PATH="$DB" MYLSM_BYTES_MODE=open bend "$ROOT/bench/smoke/public_bytes_api.bend"; then
  exit 1
fi
cmp "$DB/WAL.expected" "$DB/WAL"
rm "$DB/WAL.expected"
printf 'UNKNOWN_FORMAT_REJECTED_WITHOUT_WAL_MUTATION\n'
