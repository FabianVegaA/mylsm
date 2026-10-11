#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-snapshot-preflight.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT HUP INT TERM
MYLSM_DB_PATH="$WORK/db" bend "$ROOT/bench/smoke/snapshot_preflight.bend"
