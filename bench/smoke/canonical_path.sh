#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-canonical-path.XXXXXX")
ALIAS="$DB-alias"
BINARY=$(mktemp "${TMPDIR:-/tmp}/mylsm-canonical-path-bin.XXXXXX")
trap 'rm -rf "$DB" "$ALIAS" "$BINARY" "$DB.expected" "$ALIAS.expected"' EXIT
ln -s "$DB" "$ALIAS"
bend "$ROOT/bench/smoke/canonical_path.bend" -o "$BINARY"
MYLSM_DB_PATH="$DB" "$BINARY" > "$DB.expected"
MYLSM_DB_PATH="$ALIAS" "$BINARY" > "$ALIAS.expected"
cmp "$DB.expected" "$ALIAS.expected"
printf '%s\n' 'CANONICAL_PATH_ALIAS_PASSED'
