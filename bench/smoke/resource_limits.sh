#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-resource-limits.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
BINARY="$WORK/resource-limits"

bend "$ROOT/bench/smoke/resource_limits.bend" -o "$BINARY"
MYLSM_DB_PATH="$WORK/db" "$BINARY" > "$WORK/run.log"
grep -qxF 'RESOURCE_BATCH_LIMITS_PASSED' "$WORK/run.log"
printf '%s\n' 'RESOURCE_LIMITS_PASS'
