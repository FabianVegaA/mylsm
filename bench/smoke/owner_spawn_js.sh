#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
node "$ROOT/bench/smoke/owner_spawn_js.js" "$ROOT/src/effs/owner_spawn.js"
