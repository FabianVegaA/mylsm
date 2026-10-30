#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-retired-sst.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

bend "$ROOT/bench/smoke/owner_retired_sst.bend" -o "$WORK/fixture"
MYLSM_DB_PATH="$WORK/db" "$WORK/fixture"
