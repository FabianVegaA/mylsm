#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
node "$ROOT/bench/smoke/db_lock_js_unsupported.js" \
  "$ROOT/src/effs/db_lock.js" "$ROOT/src/effs/db_unlock.js"
