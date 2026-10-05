#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
REPORTER="$ROOT/bench/storage_codec_report.bend"
MIN_FREE_PERCENT=${MYLSM_BENCH_MIN_FREE_PERCENT:-15}

fail() { echo "$*" >&2; exit 2; }
usage() {
  echo "usage: $0 {baseline|candidate} <new-result-directory> [repeat-count>=5]" >&2
  echo "       $0 --validate <report.md>" >&2
  echo "       $0 --compare <baseline-report.md> <candidate-report.md>" >&2
}
report_field() {
  awk -F '|' -v workload="$2" -v metric="$3" -v field="$4" '
    $2 ~ "^[[:space:]]*" workload "[[:space:]]*$" && $3 ~ "^[[:space:]]*" metric "[[:space:]]*$" {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $field); print $field; exit
    }
  ' "$1"
}

case "$MIN_FREE_PERCENT" in ''|*[!0-9]*) fail "MYLSM_BENCH_MIN_FREE_PERCENT must be an integer" ;; esac
(( MIN_FREE_PERCENT >= 1 && MIN_FREE_PERCENT <= 100 )) || fail "minimum free disk percent must be between 1 and 100"

MODE=${1:-}
case "$MODE" in
  baseline|candidate) ;;
  --validate)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    [[ -f $2 ]] || fail "report not found: $2"
    rg -q '^comparison_valid=true$' "$2" || fail "report is incomplete or invalid: $2"
    REPEATS=$(awk -F= '/^repeats=/{print $2}' "$2")
    RAW=$(sed -n 's/^raw_samples=//p' "$2")
    [[ $REPEATS =~ ^[0-9]+$ && $REPEATS -ge 5 && -f $RAW ]] || fail "report has invalid sample metadata: $2"
    EXPECTED=$((REPEATS * 4))
    awk -F '\t' -v expected="$EXPECTED" -v repeats="$REPEATS" '
      NR == 1 { next }
      NR == 2 { for (i=3; i<=10; i++) meta[i]=$i }
      {
        rows++
        if ($16 != "true" || $2 < 1 || $2 > repeats || seen[$1 SUBSEP $2]++ || $11 !~ /^[0-9]+$/ || $11 == 0 || $12 !~ /^[0-9]+$/ || $14 !~ /^[0-9]+$/ || $14 == 0 || $15 !~ /^[0-9]+$/) bad=1
        for (i=3; i<=10; i++) if ($i != meta[i]) bad=1
        counts[$1]++
      }
      END {
        if (rows != expected || counts["writes_4097"] != repeats || counts["writes_20485"] != repeats || counts["writes_1000000"] != repeats || counts["compaction_5x4097"] != repeats || bad) exit 1
      }
    ' "$RAW" || fail "raw sample counts or metadata do not validate: $RAW"
    for workload in writes_4097 writes_20485 writes_1000000 compaction_5x4097; do
      count=${workload#writes_}
      for metric in elapsed_ms recovery_ms max_rss_bytes database_bytes; do
        if [[ $workload == compaction_5x4097 && $metric == recovery_ms ]]; then continue; fi
        case "$metric" in
          elapsed_ms) column=11 ;;
          recovery_ms) column=12 ;;
          max_rss_bytes) column=14 ;;
          database_bytes) column=15 ;;
        esac
        values=$(awk -F '\t' -v workload="$workload" -v column="$column" '$1 == workload {print $column}' "$RAW" | tr '\n' ' ')
        stats=$(bend "$REPORTER" stats $values)
        rg -q "samples=$REPEATS$" <<< "$stats" || fail "Bend report rejected sample count for $workload"
        median=${stats#median=}
        median=${median%% *}
        spread=${stats#*spread=}
        spread=${spread%% *}
        [[ $(report_field "$2" "$workload" "$metric" 4) == "$median" && $(report_field "$2" "$workload" "$metric" 5) == "$spread" ]] || fail "reported $metric statistics do not match raw samples for $workload"
      done
      if [[ $workload != compaction_5x4097 ]]; then
        rate=$(bend "$REPORTER" rate "$count" "$(report_field "$2" "$workload" elapsed_ms 4)")
        [[ $(report_field "$2" "$workload" median_throughput_ops_s 4) == "${rate#*=}" ]] || fail "reported throughput does not match raw samples for $workload"
      fi
    done
    echo "report_validation=passed report=$2"
    exit 0
    ;;
  --compare)
    [[ $# -eq 3 ]] || { usage; exit 2; }
    [[ -f $2 && -f $3 ]] || fail "both reports must exist"
    "$0" --validate "$2" >/dev/null
    "$0" --validate "$3" >/dev/null
    for key in bend_version os architecture logical_cpus disk_device; do
      baseline_value=$(sed -n "s/^$key=//p" "$2")
      candidate_value=$(sed -n "s/^$key=//p" "$3")
      [[ -n $baseline_value && $baseline_value == "$candidate_value" ]] || fail "comparison metadata mismatch: $key"
    done
    echo '| Workload | Baseline ms | Candidate ms | Baseline RSS | Candidate RSS | Regression x100% | Gate |'
    echo '| --- | ---: | ---: | ---: | ---: | ---: | --- |'
    overall=pass
    for workload in writes_4097 writes_20485 writes_1000000 compaction_5x4097; do
      baseline_ms=$(report_field "$2" "$workload" elapsed_ms 4)
      candidate_ms=$(report_field "$3" "$workload" elapsed_ms 4)
      baseline_rss=$(report_field "$2" "$workload" max_rss_bytes 4)
      candidate_rss=$(report_field "$3" "$workload" max_rss_bytes 4)
      [[ $baseline_ms =~ ^[0-9]+$ && $candidate_ms =~ ^[0-9]+$ && $baseline_rss =~ ^[0-9]+$ && $candidate_rss =~ ^[0-9]+$ ]] || fail "missing comparison metrics for $workload"
      result=$(bend "$REPORTER" compare "$baseline_ms" "$candidate_ms" "$baseline_rss" "$candidate_rss")
      gate=${result##*status=}
      [[ $gate == pass ]] || overall=fail
      delta=${result#elapsed_regression_percent_x100=}
      delta=${delta%% *}
      echo "| $workload | $baseline_ms | $candidate_ms | $baseline_rss | $candidate_rss | $delta | $gate |"
    done
    echo "comparison_status=$overall"
    [[ $overall == pass ]] || exit 1
    exit 0
    ;;
  *) usage; exit 2 ;;
esac

[[ $# -ge 2 && $# -le 3 ]] || { usage; exit 2; }
RESULT_DIR=$2
REPEATS=${3:-5}
case "$REPEATS" in ''|*[!0-9]*) fail "repeat count must be an integer of at least 5" ;; esac
(( REPEATS >= 5 && REPEATS <= 20 )) || fail "repeat count must be between 5 and 20"
case "$RESULT_DIR" in ''|/) fail "refusing unsafe result directory: ${RESULT_DIR:-<empty>}" ;; esac
[[ ! -L "$RESULT_DIR" ]] || fail "refusing symlink result directory: $RESULT_DIR"
[[ ! -e "$RESULT_DIR" ]] || fail "result directory already exists: $RESULT_DIR"
PARENT=$(dirname -- "$RESULT_DIR")
NAME=$(basename -- "$RESULT_DIR")
[[ -d $PARENT ]] || fail "result parent must already exist: $PARENT"
PARENT=$(CDPATH= cd -- "$PARENT" && pwd -P)
RESULT_DIR="$PARENT/$NAME"
case "$NAME" in ''|.|..) fail "refusing unsafe result directory: $RESULT_DIR" ;; esac
[[ $RESULT_DIR != "$ROOT" && $RESULT_DIR != "$HOME" ]] || fail "refusing unsafe result directory: $RESULT_DIR"
[[ $RESULT_DIR != "$ROOT/.mylsm" ]] || fail "raw benchmark results cannot replace the live .mylsm directory"

read -r DISK_DEVICE DISK_TOTAL DISK_AVAILABLE < <(df -Pk "$PARENT" | awk 'NR == 2 {print $1, $2, $4}')
[[ -n ${DISK_TOTAL:-} && -n ${DISK_AVAILABLE:-} && $DISK_TOTAL -gt 0 ]] || fail "unable to determine free disk for $PARENT"
FREE_PERCENT=$((DISK_AVAILABLE * 100 / DISK_TOTAL))
(( FREE_PERCENT >= MIN_FREE_PERCENT )) || fail "refusing benchmark: free disk is ${FREE_PERCENT}% (minimum ${MIN_FREE_PERCENT}%)"

command -v bend >/dev/null 2>&1 || fail "bend is required"
if [[ $(uname -s) == Darwin ]]; then THREADS=$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN || echo 1); else THREADS=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN || echo 1); fi
COMMIT=$(git -C "$ROOT" rev-parse HEAD)
if [[ -n $(git -C "$ROOT" --no-optional-locks status --short) ]]; then DIRTY=true; else DIRTY=false; fi
BEND_VERSION=$(bend version)
OS=$(uname -s)
ARCH=$(uname -m)

mkdir -p -- "$RESULT_DIR"
RAW="$RESULT_DIR/samples.tsv"
printf 'workload\trepeat\tcommit\tdirty\tbend\tos\tarch\tthreads\tdisk_device\tdisk_free_percent\telapsed_ms\trecovery_ms\tthroughput_ops_s\tmax_rss_bytes\tdatabase_bytes\tvalid\n' > "$RAW"
echo "benchmark=$MODE result_directory=$RESULT_DIR repeats=$REPEATS"
echo "git_commit=$COMMIT git_dirty=$DIRTY bend=$BEND_VERSION os=$OS arch=$ARCH logical_cpus=$THREADS"
echo "disk_device=$DISK_DEVICE disk_free_percent=$FREE_PERCENT minimum_free_percent=$MIN_FREE_PERCENT"

run_phase3() {
  local count=$1 repeat=$2 workload="writes_$1" dir="$RESULT_DIR/data/writes-$1-run-$2" log="$RESULT_DIR/raw/writes-$1-run-$2.log"
  mkdir -p -- "$(dirname -- "$log")"
  if ! MYLSM_THREADS="$THREADS" MYLSM_BENCH_RESULT_LOG="$log" MYLSM_BENCH_TIMING_LOG="$log.timing" \
    "$ROOT/bench/workload/phase3_metrics.sh" "$count" "$dir" >"$log" 2>&1; then
    tail -60 "$log" >&2
    fail "workload failed: $workload repeat $repeat"
  fi
  local elapsed recovery throughput rss dbbytes
  elapsed=$(awk -F= '/^metric_elapsed_ms=/{v=$2} END{print v}' "$log.timing")
  recovery=$(awk -F= '/^metric_recovery_ms=/{v=$2} END{print v}' "$log.timing")
  throughput=$(awk -F= '/^throughput_ops_per_sec=/{v=$2} END{print v}' "$log.timing")
  rss=$(awk -F= '/^max_rss_bytes=/{v=$2} END{print v}' "$log")
  dbbytes=$(awk -F= '/^metric_(wal|manifest|table)_bytes=/{v+=$2} END{print v+0}' "$log.timing")
  [[ $elapsed =~ ^[0-9]+$ && $recovery =~ ^[0-9]+$ && $rss =~ ^[0-9]+$ ]] || fail "missing benchmark metrics: $workload repeat $repeat"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\ttrue\n' \
    "$workload" "$repeat" "$COMMIT" "$DIRTY" "$BEND_VERSION" "$OS" "$ARCH" "$THREADS" "$DISK_DEVICE" "$FREE_PERCENT" \
    "$elapsed" "$recovery" "${throughput:-0}" "$rss" "$dbbytes" >> "$RAW"
}

for count in 4097 20485 1000000; do
  for ((repeat=1; repeat<=REPEATS; repeat++)); do
    echo "run workload=writes_$count repeat=$repeat/$REPEATS"
    run_phase3 "$count" "$repeat"
  done
done

for ((repeat=1; repeat<=REPEATS; repeat++)); do
  workload=compaction_5x4097
  dir="$RESULT_DIR/data/compaction-run-$repeat"
  log="$RESULT_DIR/raw/compaction-run-$repeat.log"
  mkdir -p -- "$dir" "$(dirname -- "$log")" "$ROOT/.mylsm/build"
  bend "$ROOT/bench/workload/compaction.bend" -o "$ROOT/.mylsm/build/compaction-codec-bench" >"$RESULT_DIR/raw/compaction-build.log" 2>&1
  if ! MYLSM_BENCH_ENTRIES=4097 MYLSM_BENCH_DIR="$dir" python3 "$ROOT/bench/measure_rss.py" "$log" \
    "$ROOT/.mylsm/build/compaction-codec-bench" --threads "$THREADS" >"$log.rss"; then
    tail -60 "$log" >&2
    fail "workload failed: $workload repeat $repeat"
  fi
  cat "$log.rss" >> "$log"
  local_values=$(awk -F= '/case=5x4097 phase=serialization elapsed_ms=/{v=$NF} END{print v}' "$log")
  local_rss=$(awk -F= '/^max_rss_bytes=/{v=$2} END{print v}' "$log")
  local_bytes=$(awk '/case=5x4097 status=complete/ {for(i=1;i<=NF;i++) if($i ~ /^serialized_bytes=/) {split($i,a,"="); v=a[2]}} END{print v}' "$log")
  [[ $local_values =~ ^[0-9]+$ && $local_rss =~ ^[0-9]+$ ]] || fail "missing compaction metrics for repeat $repeat"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t0\t0\t%s\t%s\ttrue\n' \
    "$workload" "$repeat" "$COMMIT" "$DIRTY" "$BEND_VERSION" "$OS" "$ARCH" "$THREADS" "$DISK_DEVICE" "$FREE_PERCENT" \
    "$local_values" "$local_rss" "${local_bytes:-0}" >> "$RAW"
done

REPORT="$RESULT_DIR/report.md"
{
  echo "# Packed storage $MODE benchmark report"
  echo
  echo "comparison_valid=true"
  echo "validated_samples=$((REPEATS * 4))"
  echo "repeats=$REPEATS"
  echo "raw_samples=$RAW"
  echo "raw_logs=$RESULT_DIR/raw"
  echo "git_commit=$COMMIT"
  echo "git_dirty=$DIRTY"
  echo "bend_version=$BEND_VERSION"
  echo "os=$OS"
  echo "architecture=$ARCH"
  echo "logical_cpus=$THREADS"
  echo "disk_device=$DISK_DEVICE"
  echo "disk_free_percent=$FREE_PERCENT"
  echo
  echo "| Workload | Metric | Median | Spread | Unit |"
  echo "| --- | --- | ---: | ---: | --- |"
  for workload in writes_4097 writes_20485 writes_1000000 compaction_5x4097; do
    if [[ $workload == compaction_5x4097 ]]; then count=0; elapsed_column=11; else count=${workload#writes_}; elapsed_column=11; fi
    for metric in elapsed_ms recovery_ms max_rss_bytes database_bytes; do
      case "$metric" in
        elapsed_ms) column=$elapsed_column ;;
        recovery_ms) column=12 ;;
        max_rss_bytes) column=14 ;;
        database_bytes) column=15 ;;
      esac
      if [[ $workload == compaction_5x4097 && $metric == recovery_ms ]]; then continue; fi
      values=$(awk -F '\t' -v workload="$workload" -v column="$column" '$1 == workload {print $column}' "$RAW" | tr '\n' ' ')
      stats=$(bend "$REPORTER" stats $values)
      median=$(sed -n 's/.*median=\([0-9][0-9]*\).*/\1/p' <<< "$stats")
      spread=$(sed -n 's/.*spread=\([0-9][0-9]*\).*/\1/p' <<< "$stats")
      echo "| $workload | $metric | $median | $spread | $metric |"
    done
    if [[ $count != 0 ]]; then
      median_elapsed=$(awk -F '\t' -v workload="$workload" '$1 == workload {print $11}' "$RAW" | tr '\n' ' ' | xargs bend "$REPORTER" stats | sed -n 's/.*median=\([0-9][0-9]*\).*/\1/p')
      rate=$(bend "$REPORTER" rate "$count" "$median_elapsed")
      echo "| $workload | median_throughput_ops_s | ${rate#*=} |  | ops/s |"
    fi
  done
} > "$REPORT"

if [[ $MODE == baseline ]]; then RESULT_REPORT="$ROOT/bench/results/packed-storage-pre-0.4.0.0.md"; else RESULT_REPORT="$ROOT/bench/results/packed-storage-0.4.0.0.md"; fi
[[ ! -e $RESULT_REPORT ]] || fail "refusing to overwrite existing result report: $RESULT_REPORT"
mkdir -p -- "$(dirname -- "$RESULT_REPORT")"
cp -- "$REPORT" "$RESULT_REPORT"
echo "baseline_samples=$RAW"
echo "benchmark_report=$RESULT_REPORT"
"$0" --validate "$RESULT_REPORT"
