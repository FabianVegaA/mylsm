#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-migration-enospc.XXXXXX")
ENOSPC_DIR=${MYLSM_ENOSPC_DIR:?set MYLSM_ENOSPC_DIR to a mounted, size-limited filesystem}
RESERVE="$ENOSPC_DIR/mylsm-reserve-$$"
DESTINATION="$ENOSPC_DIR/mylsm-destination-$$"
trap 'rm -f -- "$RESERVE"; rm -rf -- "$WORK"' EXIT HUP INT TERM

case $(uname -s) in
  Linux) ;;
  *) exit 2 ;;
esac

test -d "$ENOSPC_DIR"
DATABASE="$WORK/source"
MYLSM_DB_PATH="$DATABASE" bend "$ROOT/bench/smoke/legacy_sst_io.bend" >/dev/null
MYLSM_DB_PATH="$DATABASE" MYLSM_FIXTURE_MODE=create \
  bend "$ROOT/bench/smoke/legacy_wal_io.bend" >/dev/null
BEFORE=$(find "$DATABASE" -type f -exec cksum {} \; | sort)

fallocate -l 63k "$RESERVE"
AVAILABLE=$(df -B1 --output=avail "$ENOSPC_DIR" | tail -1 | tr -d ' ')
test "$AVAILABLE" = 0

set +e
MYLSM_DB_PATH="$DATABASE" MYLSM_MIGRATE_DEST="$DESTINATION" \
  bend "$ROOT/bench/smoke/legacy_migrate.bend" >"$WORK/migration.log" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$WORK/migration.log" >&2
  printf '%s\n' 'migration unexpectedly succeeded on a full filesystem' >&2
  exit 1
fi
test ! -e "$DESTINATION"
test ! -e "$DESTINATION.restore-060.tmp"
test ! -e "$DESTINATION.migrate-060.bundle"
test "$BEFORE" = "$(find "$DATABASE" -type f -exec cksum {} \; | sort)"
printf '%s\n' MIGRATION_ENOSPC_CLEANUP_PASSED
