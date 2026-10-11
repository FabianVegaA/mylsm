#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-shared-codec.XXXXXX")
trap 'rm -rf "$DB"' EXIT
rmdir "$DB"

MYLSM_DB_PATH="$DB" bend "$ROOT/bench/smoke/shared_utf8_bytes.bend"
