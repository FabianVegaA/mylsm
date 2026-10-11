#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-public-byte-sst-cursor.XXXXXX")
trap 'rm -rf "$DB"' EXIT
rmdir "$DB"

MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/public_bytes_sst_cursor.bend"
