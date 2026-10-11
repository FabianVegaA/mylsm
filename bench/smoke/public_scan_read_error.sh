#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-public-scan-error.XXXXXX")
trap 'rm -rf "$DB"' EXIT
rmdir "$DB"

MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/public_scan_read_error.bend"
