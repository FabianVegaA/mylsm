#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
OUT=${1:?usage: acceptance_matrix.sh <output-dir> [samples]}
SAMPLES=${2:-5}
COUNT=${MYLSM_MATRIX_WRITES:-20485}
mkdir -p -- "$OUT"
export MYLSM_BENCH_RESET=1
export MYLSM_BENCH_ALLOW_LOW_DISK=${MYLSM_BENCH_ALLOW_LOW_DISK:-0}

{
  printf 'revision=%s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || cat "$ROOT/REVISION" 2>/dev/null || echo unknown)"
  printf 'host=%s\n' "$(uname -srm)"
  printf 'bend=%s\n' "$(bend version 2>/dev/null || true)"
  printf 'writes=%s samples=%s\n' "$COUNT" "$SAMPLES"
} > "$OUT/environment.txt"

for ((sample = 1; sample <= SAMPLES; sample++)); do
  bash "$ROOT/bench/workload/million_writes.sh" "$COUNT" "$OUT/million-data" > "$OUT/million-$sample.log" 2>&1
  cp "$ROOT/.mylsm/build/million-writes-result.log" "$OUT/million-$sample.result"
  bash "$ROOT/bench/workload/phase3_metrics.sh" "$COUNT" "$OUT/phase3-data" > "$OUT/phase3-$sample.log" 2>&1
done
rm -rf -- "$OUT/million-data" "$OUT/phase3-data"

if /usr/bin/time -f '%M' true > /dev/null 2>&1; then
  MYLSM_PERF_REPEATS="$SAMPLES" bash "$ROOT/bench/workload/durable_api_perf.sh" > "$OUT/durable-api-perf.log" 2>&1
else
  printf '%s\n' 'durable_api_perf skipped: /usr/bin/time has no -f (GNU time required)' > "$OUT/durable-api-perf.log"
fi

MYLSM_CURSOR_SIZES="16000 32000 64000" bash "$ROOT/bench/smoke/public_cursor_memory.sh" > "$OUT/cursor-memory.log" 2>&1
printf '%s\n' 'ACCEPTANCE MATRIX COMPLETE'
