#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
MODE=${1:-}
REQUESTED_OUTPUT=${2:-"$ROOT/.mylsm-crash-point-overhead"}
SENTINEL_NAME=.mylsm-crash-overhead
SENTINEL_CONTENT=mylsm-crash-overhead-v1

case "$MODE" in
  before|after|compare) ;;
  *) echo "usage: $0 {before|after|compare} [output-root]" >&2; exit 2 ;;
esac

validate_output_root() {
  local requested=$1
  local parent name canonical

  case "$requested" in
    ''|/) echo "refusing unsafe overhead root: ${requested:-<empty>}" >&2; return 2 ;;
  esac
  [[ ! -L "$requested" ]] || { echo "refusing symlink overhead root: $requested" >&2; return 2; }

  parent=$(dirname -- "$requested")
  name=$(basename -- "$requested")
  case "$name" in
    ''|.|..) echo "refusing unsafe overhead root: $requested" >&2; return 2 ;;
  esac

  [[ -d "$parent" ]] || { echo "overhead output parent does not exist: $parent" >&2; return 2; }
  parent=$(CDPATH= cd -- "$parent" && pwd -P)
  canonical="$parent/$name"
  [[ "$canonical" != / && "$canonical" != "$ROOT" && "$canonical" != "$HOME" ]] || {
    echo "refusing unsafe overhead root: $canonical" >&2
    return 2
  }
  [[ "$parent" == "$ROOT" ]] || { echo "overhead root must be a direct child of $ROOT" >&2; return 2; }
  case "$name" in
    .mylsm-crash-*) ;;
    *) echo "overhead root must start with .mylsm-crash-" >&2; return 2 ;;
  esac
  [[ ! -L "$canonical" ]] || { echo "refusing symlink overhead root: $canonical" >&2; return 2; }
  printf '%s\n' "$canonical"
}

median_three() {
  sort -n "$1" | sed -n '2p'
}

capture_phase() {
  local phase=$1 output=$2
  local phase_dir="$output/$phase"
  local timings="$phase_dir/elapsed-ms.txt"
  local repetition log elapsed data_dir

  [[ ! -e "$phase_dir" ]] || { echo "overhead phase already exists: $phase_dir" >&2; return 2; }
  mkdir -p -- "$phase_dir"
  : >"$timings"
  unset MYLSM_CRASH_POINT

  for repetition in 1 2 3; do
    log="$phase_dir/run-$repetition.log"
    data_dir="$phase_dir/data-$repetition"
    MYLSM_BENCH_RESET=1 "$ROOT/bench/workload/million_writes.sh" 4096 "$data_dir" >"$log" 2>&1
    elapsed=$(awk -F= '/^elapsed_ms=/{value=$2} END{print value}' "$log")
    case "$elapsed" in
      ''|*[!0-9]*) echo "missing elapsed_ms in $log" >&2; return 1 ;;
    esac
    printf '%s\n' "$elapsed" >>"$timings"
    rm -rf -- "$data_dir"
    echo "overhead_phase=$phase repetition=$repetition elapsed_ms=$elapsed"
  done

  echo "overhead_phase=$phase median_elapsed_ms=$(median_three "$timings")"
}

compare_phases() {
  local output=$1
  local before_file="$output/before/elapsed-ms.txt"
  local after_file="$output/after/elapsed-ms.txt"
  local before after ratio status

  [[ -f "$before_file" ]] || { echo "missing before measurements: $before_file" >&2; return 2; }
  [[ -f "$after_file" ]] || { echo "missing after measurements: $after_file" >&2; return 2; }
  before=$(median_three "$before_file")
  after=$(median_three "$after_file")
  ratio=$(awk -v before="$before" -v after="$after" 'BEGIN { if (after == 0) print "invalid"; else printf "%.4f", before / after }')
  status=$(awk -v before="$before" -v after="$after" 'BEGIN { if (after > 0 && before / after >= 0.90) print "pass"; else print "fail" }')
  echo "crash_point_overhead before_median_ms=$before after_median_ms=$after throughput_ratio=$ratio baseline_floor=0.90 status=$status"
  [[ "$status" == pass ]]
}

OUTPUT=$(validate_output_root "$REQUESTED_OUTPUT")

case "$MODE" in
  before)
    if [[ -e "$OUTPUT" ]]; then
      [[ ${MYLSM_CRASH_OVERHEAD_RESET:-0} == 1 ]] || {
        echo "overhead root already exists: $OUTPUT" >&2
        echo "Set MYLSM_CRASH_OVERHEAD_RESET=1 to remove it." >&2
        exit 2
      }
      [[ -d "$OUTPUT" ]] || { echo "overhead root is not a directory: $OUTPUT" >&2; exit 2; }
      [[ -f "$OUTPUT/$SENTINEL_NAME" ]] || { echo "refusing unowned overhead root: $OUTPUT" >&2; exit 2; }
      grep -qxF "$SENTINEL_CONTENT" "$OUTPUT/$SENTINEL_NAME" || { echo "invalid overhead sentinel: $OUTPUT" >&2; exit 2; }
      rm -rf -- "$OUTPUT"
    fi
    mkdir -p -- "$OUTPUT"
    printf '%s\n' "$SENTINEL_CONTENT" >"$OUTPUT/$SENTINEL_NAME"
    capture_phase before "$OUTPUT"
    ;;
  after)
    [[ -d "$OUTPUT/before" ]] || { echo "before measurements are required" >&2; exit 2; }
    capture_phase after "$OUTPUT"
    ;;
  compare)
    compare_phases "$OUTPUT"
    ;;
esac
