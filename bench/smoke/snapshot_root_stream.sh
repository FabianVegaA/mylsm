#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-snapshot-root-stream.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT HUP INT TERM
MYLSM_DB_PATH="$WORK/db" bend "$ROOT/bench/smoke/snapshot_root_stream.bend"
