#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-migration-file-limit.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT HUP INT TERM
DATABASE="$WORK/source"
DESTINATION="$WORK/destination"

case $(uname -s) in
  Darwin|Linux) ;;
  *) exit 2 ;;
esac

MYLSM_DB_PATH="$DATABASE" bend "$ROOT/bench/smoke/legacy_sst_io.bend" >/dev/null
MYLSM_DB_PATH="$DATABASE" MYLSM_FIXTURE_MODE=create \
  bend "$ROOT/bench/smoke/legacy_wal_io.bend" >/dev/null
BEFORE=$(find "$DATABASE" -type f -exec cksum {} \; | sort)

set +e
(
  ulimit -c 0
  ulimit -f 0
  MYLSM_DB_PATH="$DATABASE" MYLSM_MIGRATE_DEST="$DESTINATION" \
    bend "$ROOT/bench/smoke/legacy_migrate.bend"
) >"$WORK/migration.log" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  printf '%s\n' 'migration unexpectedly succeeded under the file-size limit' >&2
  exit 1
fi
test ! -e "$DESTINATION"
test ! -e "$DESTINATION.restore-060.tmp"
test ! -e "$DESTINATION.migrate-060.bundle"
test "$BEFORE" = "$(find "$DATABASE" -type f -exec cksum {} \; | sort)"
printf '%s\n' MIGRATION_FILE_LIMIT_PASSED
