#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DESTINATION=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-restore-io.XXXXXX")
TEMP_DESTINATION=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-restore-temp.XXXXXX")
trap 'rm -rf "$DESTINATION" "$TEMP_DESTINATION"' EXIT
rmdir "$DESTINATION"
mkdir "$TEMP_DESTINATION.restore-060.tmp"

MYLSM_RESTORE_DESTINATION="$DESTINATION" \
MYLSM_RESTORE_INVALID_DESTINATION="$DESTINATION.invalid" \
MYLSM_RESTORE_TEMP_DESTINATION="$TEMP_DESTINATION" \
  bend "$ROOT/bench/smoke/public_restore_io.bend"
[[ ! -e "$DESTINATION.invalid" ]]
[[ -d "$TEMP_DESTINATION.restore-060.tmp" ]]
