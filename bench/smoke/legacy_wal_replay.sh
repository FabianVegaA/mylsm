#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
bend "$ROOT/bench/smoke/legacy_wal_replay.bend"
