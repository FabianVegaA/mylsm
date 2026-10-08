#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd -P)"
case $(uname -s) in
  Linux) ;;
  *) printf '%s\n' 'This workload requires Linux GNU time.' >&2; exit 2 ;;
esac

work="$(mktemp -d "${TMPDIR:-/tmp}/mylsm-durable-perf.XXXXXX")"
trap 'rm -rf "$work"' EXIT
binary="$work/durable_api_perf"
generated="$work/durable_api_perf.c"
samples="${MYLSM_PERF_SAMPLES:-$root/bench/results/durable-api-0.5.0.0-performance-samples.tsv}"
writes="${MYLSM_PERF_WRITES:-1000}"
repeats="${MYLSM_PERF_REPEATS:-5}"
compiler="${MYLSM_BEND_CC:-clang}"

bend "$root/bench/workload/durable_api_perf.bend" -o "$generated"
"$compiler" -O2 "$generated" -o "$binary"

mkdir -p "$(dirname "$samples")"
printf 'mode\trun\twrites\telapsed_ms\tlatency_us\tthroughput_ops_s\tmax_rss_kb\tdisk_kb\trecovery_ms\n' > "$samples"

measure() {
  local mode="$1" run="$2"
  local dir="$work/$mode-$run" log="$work/$mode-$run.log" rss="$work/$mode-$run.rss"
  rm -rf "$dir"
  MYLSM_PERF_MODE=seed MYLSM_PERF_PATH="$dir" MYLSM_PERF_WRITES=0 "$binary" >/dev/null
  MYLSM_PERF_MODE="$mode" MYLSM_PERF_PATH="$dir" MYLSM_PERF_WRITES="$writes" /usr/bin/time -f '%M' -o "$rss" "$binary" > "$log"
  local elapsed latency throughput recovery disk
  elapsed="$(sed -n 's/^writes=.* elapsed_ms=//p' "$log")"
  latency="$(sed -n 's/^latency_us=//p' "$log")"
  throughput="$(sed -n 's/^throughput_ops_s=//p' "$log")"
  disk="$(du -sk "$dir" | cut -f1)"
  local recovery_mode
  if [[ "$mode" == public ]]; then recovery_mode=public_recover; else recovery_mode=internal_recover; fi
  MYLSM_PERF_MODE="$recovery_mode" MYLSM_PERF_PATH="$dir" MYLSM_PERF_WRITES=0 "$binary" > "$work/$mode-$run-recovery.log"
  recovery="$(sed -n 's/^recovery_ms=//p' "$work/$mode-$run-recovery.log")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$mode" "$run" "$writes" "$elapsed" "$latency" "$throughput" "$(cat "$rss")" "$disk" "$recovery" >> "$samples"
}

for ((run = 1; run <= repeats; run++)); do
  measure internal "$run"
  measure public "$run"
done

cat "$samples"
