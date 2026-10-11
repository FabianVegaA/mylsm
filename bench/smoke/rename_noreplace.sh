#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-rename-noreplace.XXXXXX")
BINARY=$(mktemp "${TMPDIR:-/tmp}/mylsm-rename-noreplace-bin.XXXXXX")
trap 'rm -rf "$WORK" "$BINARY"' EXIT
mkdir "$WORK/source" "$WORK/existing"
mkdir "$WORK/source-again"
bend "$ROOT/bench/smoke/rename_noreplace.bend" -o "$BINARY"
MYLSM_RENAME_SOURCE="$WORK/source" \
MYLSM_RENAME_SOURCE_AGAIN="$WORK/source-again" \
MYLSM_RENAME_EXISTING="$WORK/existing" \
MYLSM_RENAME_FINAL="$WORK/final" \
  "$BINARY"
test -d "$WORK/source"
test -d "$WORK/existing"
test ! -e "$WORK/source-again"
test -d "$WORK/final"
