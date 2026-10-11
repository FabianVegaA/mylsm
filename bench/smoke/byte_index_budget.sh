#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-index-budget.XXXXXX")
trap 'rm -rf "$DB"' EXIT
MYLSM_DB_PATH="$DB/oversized.sst" bend "$ROOT/bench/smoke/byte_index_budget.bend"
