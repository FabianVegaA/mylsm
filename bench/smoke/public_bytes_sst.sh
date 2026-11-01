#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-byte-sst.XXXXXX")
NEW_EMPTY=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-byte-empty.XXXXXX")
SST_ONLY="$DB/sst-only"
CORRUPT="$DB/corrupt"
MISSING="$DB/missing-manifest"
NO_LOCK="$DB/no-lock"
LEGACY="$DB/generation-four"
FLUSH_DELTA="$DB/flush-delta"
trap 'rm -rf "$DB" "$NEW_EMPTY"' EXIT
rmdir "$DB"
rmdir "$NEW_EMPTY"

copy_db() {
  mkdir -p -- "$2"
  find "$1" -maxdepth 1 -type f -exec cp -p {} "$2/" \;
}

bash "$ROOT/bench/smoke/public_scan_reference.sh"
bash "$ROOT/bench/smoke/public_scan_read_error.sh"
bash "$ROOT/bench/smoke/public_cursor_edges.sh"
bash "$ROOT/bench/smoke/public_bytes_sst_cursor.sh"
MYLSM_DB_PATH="$NEW_EMPTY" bend "$ROOT/bench/smoke/byte_manifest_new_empty.bend"
MYLSM_DB_PATH="$DB" MYLSM_BYTES_MODE=create bend "$ROOT/bench/smoke/public_bytes_api.bend"
test -s "$DB/SST.00000002"
MYLSM_DB_PATH="$FLUSH_DELTA" bend "$ROOT/bench/smoke/byte_flush_clears_delta.bend"
copy_db "$DB" "$DB/batch-stats"
MYLSM_DB_PATH="$DB/batch-stats" bend "$ROOT/bench/smoke/byte_sst_batch_stats.bend"
copy_db "$DB" "$SST_ONLY"
truncate -s 8 "$SST_ONLY/WAL"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/public_bytes_sst_only.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/byte_recovery_delta.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/byte_sst_delta_flush.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/byte_sst_delta_compact.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/byte_recovery_delta.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/public_bytes_sst_only.bend"
MYLSM_DB_PATH="$DB" MYLSM_BYTES_MODE=open bend "$ROOT/bench/smoke/public_bytes_api.bend"
copy_db "$DB" "$LEGACY"
cp "$LEGACY/SST.00000002" "$LEGACY/SST"
truncate -s 8 "$LEGACY/WAL"
MYLSM_DB_PATH="$LEGACY" bend "$ROOT/bench/smoke/byte_manifest_legacy_open.bend" >/dev/null
LEGACY_BEFORE=$(cksum "$LEGACY/MANIFEST" "$LEGACY/WAL" "$LEGACY/SST")
LEGACY_OUTPUT=$(MYLSM_DB_PATH="$LEGACY" bend "$ROOT/bench/smoke/byte_manifest_legacy_open.bend")
printf '%s\n' "$LEGACY_OUTPUT"
rg -qxF 'LEGACY_MANIFEST_OPEN_PASSED' <<<"$LEGACY_OUTPUT"
LEGACY_AFTER=$(cksum "$LEGACY/MANIFEST" "$LEGACY/WAL" "$LEGACY/SST")
test "$LEGACY_BEFORE" = "$LEGACY_AFTER"
BEFORE=$(cksum "$DB/LOCK" "$DB/MANIFEST" "$DB/WAL" "$DB/SST.00000002")
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/format_inspect_public.bend"
AFTER=$(cksum "$DB/LOCK" "$DB/MANIFEST" "$DB/WAL" "$DB/SST.00000002")
test "$BEFORE" = "$AFTER"
copy_db "$DB" "$NO_LOCK"
rm "$NO_LOCK/LOCK"
MYLSM_DB_PATH="$NO_LOCK" bend "$ROOT/bench/smoke/format_inspect_missing_lock.bend"
test ! -e "$NO_LOCK/LOCK"
copy_db "$DB" "$CORRUPT"
printf '\001' | dd of="$CORRUPT/MANIFEST" bs=1 seek=55 conv=notrunc 2>/dev/null
MYLSM_DB_PATH="$CORRUPT" bend "$ROOT/bench/smoke/byte_manifest_reject.bend"
MYLSM_DB_PATH="$CORRUPT" bend "$ROOT/bench/smoke/format_inspect_corrupt.bend"
copy_db "$SST_ONLY" "$MISSING"
rm "$MISSING/MANIFEST"
MYLSM_DB_PATH="$MISSING" bend "$ROOT/bench/smoke/byte_manifest_io.bend"
cp "$SST_ONLY/MANIFEST" "$MISSING/MANIFEST"
MYLSM_DB_PATH="$MISSING" bend "$ROOT/bench/smoke/public_bytes_sst_only.bend"
