#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-byte-sst.XXXXXX")
SST_ONLY="$DB/sst-only"
CORRUPT="$DB/corrupt"
MISSING="$DB/missing-manifest"
NO_LOCK="$DB/no-lock"
FLUSH_DELTA="$DB/flush-delta"
trap 'rm -rf "$DB"' EXIT
rmdir "$DB"

bash "$ROOT/bench/smoke/public_scan_reference.sh"
bash "$ROOT/bench/smoke/public_scan_read_error.sh"
bash "$ROOT/bench/smoke/public_cursor_edges.sh"
bash "$ROOT/bench/smoke/public_bytes_sst_cursor.sh"
MYLSM_DB_PATH="$DB" MYLSM_BYTES_MODE=create bend "$ROOT/bench/smoke/public_bytes_api.bend"
test -s "$DB/SST"
MYLSM_DB_PATH="$FLUSH_DELTA" bend "$ROOT/bench/smoke/byte_flush_clears_delta.bend"
cp -R "$DB" "$DB/batch-stats"
MYLSM_DB_PATH="$DB/batch-stats" bend "$ROOT/bench/smoke/byte_sst_batch_stats.bend"
cp -R "$DB" "$SST_ONLY"
truncate -s 8 "$SST_ONLY/WAL"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/public_bytes_sst_only.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/byte_recovery_delta.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/byte_sst_delta_flush.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/byte_sst_delta_compact.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/byte_recovery_delta.bend"
MYLSM_DB_PATH="$SST_ONLY" bend "$ROOT/bench/smoke/public_bytes_sst_only.bend"
MYLSM_DB_PATH="$DB" MYLSM_BYTES_MODE=open bend "$ROOT/bench/smoke/public_bytes_api.bend"
BEFORE=$(cksum "$DB/LOCK" "$DB/MANIFEST" "$DB/WAL" "$DB/SST")
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/format_inspect_public.bend"
AFTER=$(cksum "$DB/LOCK" "$DB/MANIFEST" "$DB/WAL" "$DB/SST")
test "$BEFORE" = "$AFTER"
cp -R "$DB" "$NO_LOCK"
rm "$NO_LOCK/LOCK"
MYLSM_DB_PATH="$NO_LOCK" bend "$ROOT/bench/smoke/format_inspect_missing_lock.bend"
test ! -e "$NO_LOCK/LOCK"
cp -R "$DB" "$CORRUPT"
printf '\001' | dd of="$CORRUPT/MANIFEST" bs=1 seek=55 conv=notrunc 2>/dev/null
MYLSM_DB_PATH="$CORRUPT" bend "$ROOT/bench/smoke/byte_manifest_reject.bend"
MYLSM_DB_PATH="$CORRUPT" bend "$ROOT/bench/smoke/format_inspect_corrupt.bend"
cp -R "$SST_ONLY" "$MISSING"
rm "$MISSING/MANIFEST"
MYLSM_DB_PATH="$MISSING" bend "$ROOT/bench/smoke/byte_manifest_io.bend"
cp "$SST_ONLY/MANIFEST" "$MISSING/MANIFEST"
MYLSM_DB_PATH="$MISSING" bend "$ROOT/bench/smoke/public_bytes_sst_only.bend"
