#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-spawn-lock.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
MYLSM_SPAWN_DB="$WORK/db" \
MYLSM_SPAWN_CLEAR="$WORK/clear" \
MYLSM_SPAWN_INHERITED="$WORK/inherited" \
  bend "$ROOT/bench/smoke/owner_spawn_lock.bend"
