#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-byte-block-reader.XXXXXX")
trap 'rm -rf "$DB"' EXIT
rmdir "$DB"

MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/byte_block_reader.bend"
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/sst_cursor.bend"
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/visible_cursor.bend"
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/byte_sst_read_at.bend"
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/byte_block_corruption.bend"
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/byte_sst_root_corruption.bend"
MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/byte_sst_recovery.bend"
MYLSM_SST_PATH="$DB/SST" bend "$ROOT/bench/smoke/byte_sst_metadata.bend"
MYLSM_SST_PATH="$DB/SST" bend "$ROOT/bench/smoke/byte_block_invalid_offset.bend"
MYLSM_SST_PATH="$DB/SST" bend "$ROOT/bench/smoke/byte_block_truncated.bend"
