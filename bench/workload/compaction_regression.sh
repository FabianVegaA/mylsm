#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
MODE=${1:-baseline}
REQUESTED_OUTPUT=${2:-"$ROOT/.mylsm-compaction-regression"}
MIN_FREE_PERCENT=15

case "$MODE" in
  baseline|linear-core|partitioned-pure|final|short) ;;
  *)
    echo "usage: $0 {baseline|linear-core|partitioned-pure|final|short} [output-directory]" >&2
    exit 2
    ;;
esac

case "$REQUESTED_OUTPUT" in
  ''|/)
    echo "refusing unsafe output directory: ${REQUESTED_OUTPUT:-<empty>}" >&2
    exit 2
    ;;
esac

if [[ -L "$REQUESTED_OUTPUT" ]]; then
  echo "refusing symlink output directory: $REQUESTED_OUTPUT" >&2
  exit 2
fi

OUTPUT_PARENT=$(dirname -- "$REQUESTED_OUTPUT")
OUTPUT_NAME=$(basename -- "$REQUESTED_OUTPUT")
mkdir -p -- "$OUTPUT_PARENT"
OUTPUT_PARENT=$(CDPATH= cd -- "$OUTPUT_PARENT" && pwd -P)
OUTPUT_DIR="$OUTPUT_PARENT/$OUTPUT_NAME"

case "$OUTPUT_NAME" in
  ''|.|..) echo "refusing unsafe output directory: $OUTPUT_DIR" >&2; exit 2 ;;
esac
if [[ "$OUTPUT_DIR" == "$ROOT" || "$OUTPUT_DIR" == "$HOME" ]]; then
  echo "refusing unsafe output directory: $OUTPUT_DIR" >&2
  exit 2
fi
if [[ -e "$OUTPUT_DIR" ]]; then
  if [[ ${MYLSM_BENCH_RESET:-0} != 1 ]]; then
    echo "benchmark directory already exists: $OUTPUT_DIR" >&2
    echo "Use a different directory or set MYLSM_BENCH_RESET=1 to delete it." >&2
    exit 2
  fi
  [[ -d "$OUTPUT_DIR" ]] || { echo "output path is not a directory: $OUTPUT_DIR" >&2; exit 2; }
  rm -rf -- "$OUTPUT_DIR"
fi
mkdir -p -- "$OUTPUT_DIR/pure"

read -r DISK_TOTAL DISK_AVAILABLE < <(df -Pk "$OUTPUT_DIR" | awk 'NR == 2 { print $2, $4 }')
if [[ -z ${DISK_TOTAL:-} || -z ${DISK_AVAILABLE:-} || "$DISK_TOTAL" == 0 ]]; then
  echo "unable to determine free disk for $OUTPUT_DIR" >&2
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
command -v perl >/dev/null 2>&1 || { echo "perl is required for portable timeout gates" >&2; exit 127; }

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
(( THREADS >= 1 && THREADS <= 256 )) || { echo "MYLSM_THREADS must be between 1 and 256" >&2; exit 2; }

RESULT="$OUTPUT_DIR/result-$MODE.log"
exec > >(tee "$RESULT") 2>&1

COMMIT=$(git -C "$ROOT" rev-parse HEAD)
if [[ -n $(git -C "$ROOT" --no-optional-locks status --short) ]]; then DIRTY=true; else DIRTY=false; fi
BEND_VERSION=$(bend version)
OS_NAME=$(uname -s)
ARCH=$(uname -m)

echo "benchmark=compaction_regression"
echo "mode=$MODE"
echo "bend_version=$BEND_VERSION"
echo "os=$OS_NAME architecture=$ARCH logical_cpus=$THREADS"
echo "git_commit=$COMMIT git_dirty=$DIRTY"
echo "disk_total_kib=$DISK_TOTAL disk_available_kib=$DISK_AVAILABLE disk_free_percent=$FREE_PERCENT"
echo "minimum_free_percent=$MIN_FREE_PERCENT comparison_valid=$COMPARISON_VALID"
echo "memtable_cap=4096 l0_table_threshold=4 first_flush_write_count=4097 first_compaction_write_count=20485"
echo "output_directory=$OUTPUT_DIR"
if [[ "$COMPARISON_VALID" == false ]]; then
  echo "comparison_invalid_reason=low_disk_override"
fi

BUILD_DIR="$ROOT/.mylsm/build"
BINARY="$BUILD_DIR/compaction-bench"
mkdir -p -- "$BUILD_DIR"
echo "phase=build status=starting"
bend "$ROOT/bench/workload/compaction.bend" -o "$BINARY"
echo "phase=build status=complete"
LAST_COMPLETED=build

run_with_timeout() {
  local seconds=$1
  shift
  perl -e '
    use strict;
    use warnings;
    my $limit = shift @ARGV;
    my $pid = fork();
    die "fork failed: $!\n" unless defined $pid;
    if ($pid == 0) {
      setpgrp(0, 0);
      exec @ARGV;
      exit 127;
    }
    local $SIG{ALRM} = sub {
      kill "TERM", -$pid;
      select undef, undef, undef, 2;
      kill "KILL", -$pid;
      exit 124;
    };
    alarm $limit;
    waitpid($pid, 0);
    alarm 0;
    my $status = $?;
    exit(($status & 127) ? 128 + ($status & 127) : ($status >> 8));
  ' "$seconds" "$@"
}

run_gate() {
  local phase=$1
  local timeout_seconds=$2
  shift 2
  echo "phase=$phase status=starting timeout_seconds=$timeout_seconds"
  if run_with_timeout "$timeout_seconds" "$@"; then
    echo "phase=$phase status=complete"
    LAST_COMPLETED=$phase
  else
    local rc=$?
    echo "phase=$phase status=failed exit_code=$rc last_completed_phase=$LAST_COMPLETED" >&2
    exit "$rc"
  fi
}

if [[ "$MODE" != short ]]; then
  run_gate durable_4096_no_flush "${MYLSM_BENCH_TIMEOUT_4096:-120}" env MYLSM_THREADS="$THREADS" "$ROOT/bench/workload/million_writes.sh" 4096 "$OUTPUT_DIR/durable-4096"
  run_gate durable_4097_first_flush "${MYLSM_BENCH_TIMEOUT_4097:-300}" env MYLSM_THREADS="$THREADS" "$ROOT/bench/workload/million_writes.sh" 4097 "$OUTPUT_DIR/durable-4097"
  run_gate durable_20485_first_compaction "${MYLSM_BENCH_TIMEOUT_20485:-1800}" env MYLSM_THREADS="$THREADS" "$ROOT/bench/workload/million_writes.sh" 20485 "$OUTPUT_DIR/durable-20485"
  PURE_ENTRIES=4097
else
  PURE_ENTRIES=${MYLSM_BENCH_ENTRIES:-8}
  echo "short_validation=true durable_gates_skipped=true"
fi

run_gate pure_five_run_compaction "${MYLSM_BENCH_TIMEOUT_PURE:-1800}" env MYLSM_BENCH_ENTRIES="$PURE_ENTRIES" MYLSM_BENCH_DIR="$OUTPUT_DIR/pure" "$BINARY" --threads "$THREADS"
for RUNS in 1 4 5; do
  grep -q "^case=${RUNS}x${PURE_ENTRIES} correctness=pass newest_wins=pass tombstone=pass odd_disjoint_runs=pass output_parse=pass$" "$RESULT" || {
    echo "correctness gate failed: pure ${RUNS}x${PURE_ENTRIES} compaction" >&2
    exit 1
  }
done
echo "phase=pure_correctness status=complete merged_count=pass newest_value=pass tombstone=pass odd_disjoint_runs=pass output_parse=pass"
echo "benchmark_status=complete last_completed_phase=$LAST_COMPLETED"
echo "result_log=$RESULT"
