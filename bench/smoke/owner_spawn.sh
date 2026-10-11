#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BIN=$(mktemp "${TMPDIR:-/tmp}/mylsm-owner-spawn.XXXXXX")
trap 'rm -f -- "$BIN"' EXIT
bend "$ROOT/bench/smoke/owner_spawn.bend" -o "$BIN"
"$BIN" | grep -qx 'OWNER_SPAWN_PASSED'
printf '%s\n' 'OWNER_SPAWN_NATIVE_PASSED'
