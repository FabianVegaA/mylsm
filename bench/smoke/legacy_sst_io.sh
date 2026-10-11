#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-legacy-sst.XXXXXX")
trap 'rm -rf "$DB"' EXIT
rmdir "$DB"

MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/legacy_sst_io.bend"
MYLSM_DB_PATH="$DB" MYLSM_FIXTURE_MODE=create bend "$ROOT/bench/smoke/legacy_wal_io.bend"
BEFORE=$(cksum "$DB/LOCK" "$DB/MANIFEST" "$DB/l0/0.tbl" "$DB/WAL")
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/legacy_format_inspect.bend"
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/legacy_sst_validate.bend"
SOURCE_REPORT=$(MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/legacy_source_validate.bend")
printf '%s\n' "$SOURCE_REPORT"
SOURCE_BYTES=$(($(wc -c < "$DB/l0/0.tbl") + $(wc -c < "$DB/WAL")))
rg -q "LEGACY_SOURCE_ENCODED_BYTES=$SOURCE_BYTES" <<< "$SOURCE_REPORT"
AFTER=$(cksum "$DB/LOCK" "$DB/MANIFEST" "$DB/l0/0.tbl" "$DB/WAL")
test "$BEFORE" = "$AFTER"
cp -R "$DB" "$DB-wal-corrupt"
printf '\001' | dd of="$DB-wal-corrupt/WAL" bs=1 seek=0 conv=notrunc 2>/dev/null
CORRUPT_WAL_BEFORE=$(cksum "$DB-wal-corrupt/LOCK" "$DB-wal-corrupt/MANIFEST" "$DB-wal-corrupt/l0/0.tbl" "$DB-wal-corrupt/WAL")
MYLSM_DB_PATH="$DB-wal-corrupt" MYLSM_EXPECT_INVALID=true bend "$ROOT/bench/smoke/legacy_source_validate.bend"
CORRUPT_WAL_AFTER=$(cksum "$DB-wal-corrupt/LOCK" "$DB-wal-corrupt/MANIFEST" "$DB-wal-corrupt/l0/0.tbl" "$DB-wal-corrupt/WAL")
test "$CORRUPT_WAL_BEFORE" = "$CORRUPT_WAL_AFTER"
cp -R "$DB" "$DB-corrupt"
printf '\001' | dd of="$DB-corrupt/l0/0.tbl" bs=1 seek=0 conv=notrunc 2>/dev/null
CORRUPT_BEFORE=$(cksum "$DB-corrupt/LOCK" "$DB-corrupt/MANIFEST" "$DB-corrupt/l0/0.tbl")
MYLSM_DB_PATH="$DB-corrupt" bend "$ROOT/bench/smoke/legacy_sst_reject.bend"
CORRUPT_AFTER=$(cksum "$DB-corrupt/LOCK" "$DB-corrupt/MANIFEST" "$DB-corrupt/l0/0.tbl")
test "$CORRUPT_BEFORE" = "$CORRUPT_AFTER"
cp -R "$DB" "$DB-aggregate"
MYLSM_DB_PATH="$DB-aggregate" bend "$ROOT/bench/smoke/legacy_sst_multi_manifest.bend"
truncate -s 67108864 "$DB-aggregate/l0/1.tbl"
AGGREGATE_BEFORE=$(cksum "$DB-aggregate/LOCK" "$DB-aggregate/MANIFEST" "$DB-aggregate/l0/0.tbl" "$DB-aggregate/l0/1.tbl")
MYLSM_DB_PATH="$DB-aggregate" bend "$ROOT/bench/smoke/legacy_sst_aggregate_limit.bend"
AGGREGATE_AFTER=$(cksum "$DB-aggregate/LOCK" "$DB-aggregate/MANIFEST" "$DB-aggregate/l0/0.tbl" "$DB-aggregate/l0/1.tbl")
test "$AGGREGATE_BEFORE" = "$AGGREGATE_AFTER"
truncate -s 67108865 "$DB/l0/0.tbl"
LARGE_BEFORE=$(wc -c < "$DB/l0/0.tbl" | tr -d ' ')
MYLSM_SST_PATH="$DB/l0/0.tbl" MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/legacy_sst_limit.bend"
LARGE_AFTER=$(wc -c < "$DB/l0/0.tbl" | tr -d ' ')
test "$LARGE_BEFORE" = "$LARGE_AFTER"
