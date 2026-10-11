#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
node "$ROOT/bench/smoke/rename_noreplace_js_unsupported.js" \
  "$ROOT/src/effs/rename_noreplace.js"
