#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-legacy-unknown.XXXXXX")
SOURCE="$WORK/source"
UNKNOWN="$WORK/unknown"
DESTINATION="$WORK/destination"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$SOURCE"
MYLSM_DB_PATH="$SOURCE" bend "$ROOT/bench/smoke/legacy_sst_io.bend"
MYLSM_DB_PATH="$SOURCE" MYLSM_FIXTURE_MODE=create \
  bend "$ROOT/bench/smoke/legacy_wal_io.bend"
cp -R "$SOURCE" "$UNKNOWN"
before=$(find "$UNKNOWN" -type f -exec cksum {} \; | sort)
printf '\004' | dd of="$UNKNOWN/MANIFEST" bs=1 seek=11 conv=notrunc 2>/dev/null
changed=$(find "$UNKNOWN" -type f -exec cksum {} \; | sort)
test "$before" != "$changed"

MYLSM_DB_PATH="$UNKNOWN" MYLSM_MIGRATE_DEST="$DESTINATION" \
  bend "$ROOT/bench/smoke/legacy_migration_unknown.bend"
test ! -e "$DESTINATION"
test ! -e "$DESTINATION.migrate-060.bundle"
test ! -e "$DESTINATION.migrate-060.bundle.backup-060.tmp"
test "$changed" = "$(find "$UNKNOWN" -type f -exec cksum {} \; | sort)"
printf '%s\n' LEGACY_MIGRATION_UNKNOWN_VERSION_PASS
