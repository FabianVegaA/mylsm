#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
SOURCE="$ROOT/bench/workload/million_writes.bend"
BUILD_DIR="$ROOT/.mylsm/build"
BINARY="$BUILD_DIR/million-writes"
COUNT=${1:-1000000}
REQUESTED_DATA_DIR=${2:-"$ROOT/.mylsm-million-write-data"}
RESULT="$BUILD_DIR/million-writes-result.log"
RUN_RESULT="$BUILD_DIR/million-writes-timing.log"
MIN_FREE_PERCENT=15

case "$COUNT" in
  ''|*[!0-9]*) echo "write count must be a positive integer" >&2; exit 2 ;;
esac
if (( COUNT < 1 || COUNT > 4294967295 )); then
  echo "write count must be between 1 and 4294967295" >&2
  exit 2
fi

case "$REQUESTED_DATA_DIR" in
  ''|/) echo "refusing unsafe benchmark directory: ${REQUESTED_DATA_DIR:-<empty>}" >&2; exit 2 ;;
esac
if [[ -L "$REQUESTED_DATA_DIR" ]]; then
  echo "refusing symlink benchmark directory: $REQUESTED_DATA_DIR" >&2
  exit 2
fi
DATA_PARENT=$(dirname -- "$REQUESTED_DATA_DIR")
DATA_NAME=$(basename -- "$REQUESTED_DATA_DIR")
mkdir -p -- "$DATA_PARENT"
DATA_PARENT=$(CDPATH= cd -- "$DATA_PARENT" && pwd -P)
DATA_DIR="$DATA_PARENT/$DATA_NAME"
case "$DATA_NAME" in ''|.|..) echo "refusing unsafe benchmark directory: $DATA_DIR" >&2; exit 2 ;; esac
if [[ "$DATA_DIR" == "$ROOT" || "$DATA_DIR" == "$HOME" ]]; then
  echo "refusing unsafe benchmark directory: $DATA_DIR" >&2
  exit 2
fi

if [[ -e "$DATA_DIR" ]]; then
  if [[ ${MYLSM_BENCH_RESET:-0} != 1 ]]; then
    echo "benchmark directory already exists: $DATA_DIR" >&2
    echo "Use a different directory or set MYLSM_BENCH_RESET=1 to delete it." >&2
    exit 2
  fi
  [[ -d "$DATA_DIR" ]] || { echo "benchmark path is not a directory: $DATA_DIR" >&2; exit 2; }
  rm -rf -- "$DATA_DIR"
fi

read -r DISK_TOTAL DISK_AVAILABLE < <(df -Pk "$DATA_PARENT" | awk 'NR == 2 { print $2, $4 }')
if [[ -z ${DISK_TOTAL:-} || -z ${DISK_AVAILABLE:-} || "$DISK_TOTAL" == 0 ]]; then
  echo "unable to determine free disk for $DATA_PARENT" >&2
  exit 2
fi
FREE_PERCENT=$((DISK_AVAILABLE * 100 / DISK_TOTAL))
COMPARISON_VALID=true
if (( FREE_PERCENT < MIN_FREE_PERCENT )); then
  if [[ ${MYLSM_BENCH_ALLOW_LOW_DISK:-0} != 1 ]]; then
    echo "refusing benchmark: free disk is ${FREE_PERCENT}% (minimum ${MIN_FREE_PERCENT}%)" >&2
    echo "Set MYLSM_BENCH_ALLOW_LOW_DISK=1 to run a result invalid for comparison." >&2
    exit 2
  fi
  COMPARISON_VALID=false
fi

command -v bend >/dev/null 2>&1 || { echo "bend is required" >&2; exit 127; }
if [[ -n ${MYLSM_THREADS:-} ]]; then
  THREADS=$MYLSM_THREADS
elif [[ $(uname -s) == Darwin ]]; then
  THREADS=$(sysctl -n hw.logicalcpu)
elif command -v nproc >/dev/null 2>&1; then
  THREADS=$(nproc)
else
  THREADS=1
fi
case "$THREADS" in ''|*[!0-9]*) echo "MYLSM_THREADS must be an integer" >&2; exit 2 ;; esac
if (( THREADS < 1 || THREADS > 256 )); then
  echo "MYLSM_THREADS must be between 1 and 256" >&2
  exit 2
fi

# GPU device selection for `!` calls (native binaries default to GPU on).
# MYLSM_DEVICE: gpu/on (default, no flag), cpu/off (--gpu off), or a heap cap
# like 4GB/512MB (--gpu <cap>). Values are validated before being passed
# unquoted to the binary (word-splitting of "--gpu off" is intended).
GPU_MODE=${MYLSM_DEVICE:-gpu}
case "$GPU_MODE" in
  gpu|on) GPU_ARGS="" ;;
  cpu|off) GPU_ARGS="--gpu off" ;;
  [0-9]*[GgMm][Bb]) GPU_ARGS="--gpu $GPU_MODE" ;;
  *) echo "MYLSM_DEVICE must be gpu, cpu, off, or a heap cap like 4GB" >&2; exit 2 ;;
esac

# Apple clang matches the macOS SDK module maps; homebrew llvm fails to build
# the Metal .gpu artifact (module '_c_standard_library_obsolete' error).
if [[ $(uname -s) == Darwin && -z ${CC:-} ]]; then
  export CC=/usr/bin/clang
fi

mkdir -p "$BUILD_DIR"
exec > >(tee "$RESULT") 2>&1
COMMIT=$(git -C "$ROOT" rev-parse HEAD)
if [[ -n $(git -C "$ROOT" --no-optional-locks status --short) ]]; then DIRTY=true; else DIRTY=false; fi

echo "benchmark=million_writes"
echo "bend_version=$(bend version)"
echo "os=$(uname -s) architecture=$(uname -m) logical_cpus=$THREADS"
echo "gpu_mode=$GPU_MODE cc=${CC:-default}"
echo "git_commit=$COMMIT git_dirty=$DIRTY"
echo "disk_total_kib=$DISK_TOTAL disk_available_kib=$DISK_AVAILABLE disk_free_percent=$FREE_PERCENT"
echo "minimum_free_percent=$MIN_FREE_PERCENT comparison_valid=$COMPARISON_VALID"
echo "write_count=$COUNT memtable_cap=4096 l0_table_threshold=4 first_flush_write_count=4097 first_compaction_write_count=20485"
echo "data_directory=$DATA_DIR"
if [[ "$COMPARISON_VALID" == false ]]; then echo "comparison_invalid_reason=low_disk_override"; fi

echo "phase=build status=starting measured=false"
bend "$SOURCE" -o "$BINARY"
echo "phase=build status=complete measured=false"
echo "phase=durable_writes status=starting"
/usr/bin/time -p env MYLSM_BENCH_WRITES="$COUNT" MYLSM_BENCH_DIR="$DATA_DIR" "$BINARY" --threads "$THREADS" $GPU_ARGS 2>&1 | tee "$RUN_RESULT"
echo "phase=durable_writes status=complete"

grep -q "^writes_completed=$COUNT$" "$RUN_RESULT" || { echo "correctness gate failed: write count" >&2; exit 1; }
grep -q '^phase=pre_recovery samples=pass$' "$RUN_RESULT" || { echo "correctness gate failed: pre-recovery samples" >&2; exit 1; }
grep -q '^phase=post_recovery samples=pass$' "$RUN_RESULT" || { echo "correctness gate failed: post-recovery samples" >&2; exit 1; }

case "$COUNT" in
  4096) EXPECTED_SHAPE='mem_entries=0 frozen_entries=4096 l0_tables=0 l1_tables=0' ;;
  4097) EXPECTED_SHAPE='mem_entries=1 frozen_entries=4096 l0_tables=0 l1_tables=0' ;;
  20485) EXPECTED_SHAPE='mem_entries=3 frozen_entries=4096 l0_tables=2 l1_tables=0' ;;
  *) EXPECTED_SHAPE='' ;;
esac
if [[ -n "$EXPECTED_SHAPE" ]]; then
  grep -q "^phase=pre_recovery $EXPECTED_SHAPE$" "$RUN_RESULT" || { echo "correctness gate failed: pre-recovery level shape" >&2; exit 1; }
  grep -q "^phase=post_recovery $EXPECTED_SHAPE$" "$RUN_RESULT" || { echo "correctness gate failed: post-recovery level shape" >&2; exit 1; }
fi
echo "phase=correctness status=complete samples=first_middle_last recovery=pass level_shape=pass"

ELAPSED_MS=$(awk -F= '/^elapsed_ms=/{print $2}' "$RUN_RESULT" | awk 'END {print}')
if [[ -n "$ELAPSED_MS" ]] && (( ELAPSED_MS > 0 )); then
  awk -v count="$COUNT" -v elapsed_ms="$ELAPSED_MS" 'BEGIN { printf "throughput_ops_per_sec=%.2f\n", count * 1000 / elapsed_ms }'
fi

echo "result_log=$RESULT"
echo "database_preserved_at=$DATA_DIR"
