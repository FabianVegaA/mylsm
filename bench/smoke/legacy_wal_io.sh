#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-legacy-wal.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT HUP INT TERM
mkdir -p -- "$WORK/db"
MYLSM_DB_PATH="$WORK/db" MYLSM_FIXTURE_MODE=create bend "$ROOT/bench/smoke/legacy_wal_io.bend"
before=$(cksum "$WORK/db/LOCK" "$WORK/db/WAL")
MYLSM_DB_PATH="$WORK/db" MYLSM_FIXTURE_MODE=verify bend "$ROOT/bench/smoke/legacy_wal_io.bend"
after=$(cksum "$WORK/db/LOCK" "$WORK/db/WAL")
[[ "$before" == "$after" ]]
MYLSM_DB_PATH="$WORK/db" MYLSM_FIXTURE_MODE=corrupt bend "$ROOT/bench/smoke/legacy_wal_io.bend"
before=$(cksum "$WORK/db/LOCK" "$WORK/db/WAL")
MYLSM_DB_PATH="$WORK/db" MYLSM_FIXTURE_MODE=verify-invalid bend "$ROOT/bench/smoke/legacy_wal_io.bend"
after=$(cksum "$WORK/db/LOCK" "$WORK/db/WAL")
[[ "$before" == "$after" ]]
