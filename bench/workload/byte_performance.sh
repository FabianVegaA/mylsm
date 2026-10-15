#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
MODE=${1:?usage: byte_performance.sh <baseline|candidate> <result-dir> [samples]}
REQUESTED_RESULT_DIR=${2:?result directory required}
SAMPLES=${3:-8}
THREADS=${MYLSM_THREADS:-1}
CASES=${MYLSM_BYTE_BENCH_CASES:-all}
MAINTENANCE_COUNTS=${MYLSM_BYTE_BENCH_MAINTENANCE_COUNTS:-128 4096}
FIXTURE_DIR=${MYLSM_BYTE_BENCH_FIXTURE_DIR:-}

case "$MODE" in
  baseline|candidate) ;;
  *) echo "mode must be baseline or candidate" >&2; exit 2 ;;
esac
case "$SAMPLES" in
  ''|*[!0-9]*) echo "sample count must be a positive integer" >&2; exit 2 ;;
esac
if (( SAMPLES < 1 || SAMPLES > 64 )); then
  echo "sample count must be between 1 and 64" >&2
  exit 2
fi
case "$THREADS" in
  ''|*[!0-9]*) echo "MYLSM_THREADS must be an integer" >&2; exit 2 ;;
esac
if (( THREADS < 1 || THREADS > 256 )); then
  echo "MYLSM_THREADS must be between 1 and 256" >&2
  exit 2
fi
case "$CASES" in
  all|ordering|scans|maintenance|phases) ;;
  *) echo "MYLSM_BYTE_BENCH_CASES must be all, ordering, scans, maintenance, or phases" >&2; exit 2 ;;
esac
case "$REQUESTED_RESULT_DIR" in
  ''|/) echo "refusing unsafe result directory" >&2; exit 2 ;;
esac
if [[ -L "$REQUESTED_RESULT_DIR" ]]; then
  echo "refusing symlink result directory" >&2
  exit 2
fi
RESULT_PARENT=$(dirname -- "$REQUESTED_RESULT_DIR")
RESULT_NAME=$(basename -- "$REQUESTED_RESULT_DIR")
mkdir -p -- "$RESULT_PARENT"
RESULT_PARENT=$(CDPATH= cd -- "$RESULT_PARENT" && pwd -P)
RESULT_DIR="$RESULT_PARENT/$RESULT_NAME"
case "$RESULT_NAME" in ''|.|..) echo "refusing unsafe result directory" >&2; exit 2 ;; esac
if [[ "$RESULT_DIR" == "$ROOT" || "$RESULT_DIR" == "$HOME" ]]; then
  echo "refusing unsafe result directory" >&2
  exit 2
fi
if [[ -e "$RESULT_DIR" ]]; then
  if [[ ${MYLSM_BYTE_BENCH_RESET:-0} != 1 ]]; then
    echo "result directory exists: $RESULT_DIR" >&2
    exit 2
  fi
  [[ -d "$RESULT_DIR" ]] || { echo "result path is not a directory" >&2; exit 2; }
  rm -rf -- "$RESULT_DIR"
fi
mkdir -p -- "$RESULT_DIR"
DISK=$(df -Pk "$RESULT_PARENT" | awk 'NR == 2 { print $2, $4 }')
TOTAL_KIB=${DISK%% *}
FREE_KIB=${DISK##* }
if [[ -z ${TOTAL_KIB:-} || -z ${FREE_KIB:-} || "$TOTAL_KIB" == 0 ]]; then
  echo "unable to determine free disk" >&2
  exit 2
fi
FREE_PERCENT=$((FREE_KIB * 100 / TOTAL_KIB))
if (( FREE_PERCENT < 15 )); then
  echo "refusing benchmark with only ${FREE_PERCENT}% free disk" >&2
  exit 2
fi

BUILD_DIR="$ROOT/.mylsm/build"
BINARY=${MYLSM_BYTE_BENCH_BINARY:-"$BUILD_DIR/byte-performance"}
mkdir -p -- "$BUILD_DIR"
if [[ -z ${MYLSM_BYTE_BENCH_BINARY:-} ]]; then
  bend "$ROOT/bench/workload/byte_performance.bend" -o "$BINARY"
elif [[ ! -x "$BINARY" ]]; then
  echo "benchmark binary is not executable: $BINARY" >&2
  exit 2
fi
COMMIT=$(git -C "$ROOT" rev-parse HEAD)
if [[ -n $(git -C "$ROOT" --no-optional-locks status --short) ]]; then DIRTY=true; else DIRTY=false; fi
DEVICE=$(df -Pk "$RESULT_PARENT" | awk 'NR == 2 { print $1 }')
DISK_TOTAL_KIB=$(df -Pk "$RESULT_PARENT" | awk 'NR == 2 { print $2 }')
DISK_FREE_KIB=$(df -Pk "$RESULT_PARENT" | awk 'NR == 2 { print $4 }')
CLANG_VERSION=$(clang --version 2>/dev/null | head -n 1 || true)
MACHINE_MODEL=$(sysctl -n hw.model 2>/dev/null || uname -m)
printf 'mode=%s\ncommit=%s\ndirty=%s\nbend=%s\ncompiler=%s\ncompiler_flags=%s\nos=%s\narch=%s\nmachine_model=%s\nthreads=%s\ncases=%s\ndevice=%s\ndisk_total_kib=%s\ndisk_free_kib=%s\ndisk_free_percent=%s\n' \
  "$MODE" "$COMMIT" "$DIRTY" "$(bend version)" "$CLANG_VERSION" "bend-native-default" \
  "$(uname -s)" "$(uname -m)" "$MACHINE_MODEL" "$THREADS" "$CASES" "$DEVICE" \
  "$DISK_TOTAL_KIB" "$DISK_FREE_KIB" "$FREE_PERCENT" \
  > "$RESULT_DIR/metadata.txt"
printf 'sample\tscenario\tcount\tvalue_bytes\tphase\telapsed_ms\tchecksum\tpeak_rss_bytes\tbytes_on_disk\tresult\n' \
  > "$RESULT_DIR/results.tsv"
if [[ "$CASES" == all || "$CASES" == ordering ]]; then
for count in 256 1024 4096 8192; do
  for value_bytes in 32 4096; do
    sample=1
    while (( sample <= SAMPLES )); do
      log="$RESULT_DIR/${count}-${value_bytes}-${sample}.log"
      rss=$(MYLSM_BYTE_BENCH_SCENARIO=order_unique MYLSM_BYTE_BENCH_COUNT="$count" \
        MYLSM_BYTE_BENCH_VALUE_BYTES="$value_bytes" \
        python3 "$ROOT/bench/measure_rss.py" "$log" "$BINARY" --threads "$THREADS")
      row=$(grep '^scenario=' "$log")
      [[ -n "$row" ]] || { echo "missing benchmark row in $log" >&2; exit 1; }
      scenario=$(sed -n 's/.*scenario=\([^,]*\).*/\1/p' <<< "$row")
      measured_count=$(sed -n 's/.*count=\([^,]*\).*/\1/p' <<< "$row")
      measured_value_bytes=$(sed -n 's/.*value_bytes=\([^,]*\).*/\1/p' <<< "$row")
      phase=$(sed -n 's/.*phase=\([^,]*\).*/\1/p' <<< "$row")
      elapsed=$(sed -n 's/.*elapsed_ms=\([^,]*\).*/\1/p' <<< "$row")
      checksum=$(sed -n 's/.*checksum=\([^,]*\).*/\1/p' <<< "$row")
      result=$(sed -n 's/.*result=\([^,]*\).*/\1/p' <<< "$row")
      rss_bytes=${rss#max_rss_bytes=}
      [[ "$elapsed" =~ ^[0-9]+$ && "$result" == pass && "$rss_bytes" =~ ^[0-9]+$ ]] || {
        echo "invalid result row in $log" >&2
        exit 1
      }
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sample" "$scenario" "$measured_count" "$measured_value_bytes" "$phase" "$elapsed" "$checksum" "$rss_bytes" "0" "$result" \
        >> "$RESULT_DIR/results.tsv"
      sample=$((sample + 1))
    done
  done
done
for value_bytes in 32 4096; do
  sample=1
  while (( sample <= SAMPLES )); do
    log="$RESULT_DIR/overwrite-${value_bytes}-${sample}.log"
    rss=$(MYLSM_BYTE_BENCH_SCENARIO=order_overwrite MYLSM_BYTE_BENCH_COUNT=4096 \
      MYLSM_BYTE_BENCH_VALUE_BYTES="$value_bytes" \
      python3 "$ROOT/bench/measure_rss.py" "$log" "$BINARY" --threads "$THREADS")
    row=$(grep '^scenario=' "$log")
    [[ -n "$row" ]] || { echo "missing overwrite result row in $log" >&2; exit 1; }
    elapsed=$(sed -n 's/.*elapsed_ms=\([^,]*\).*/\1/p' <<< "$row")
    checksum=$(sed -n 's/.*checksum=\([^,]*\).*/\1/p' <<< "$row")
    rss_bytes=${rss#max_rss_bytes=}
    [[ "$elapsed" =~ ^[0-9]+$ && "$checksum" == 4095 && "$rss_bytes" =~ ^[0-9]+$ ]] || {
      echo "invalid overwrite result row in $log" >&2
      exit 1
    }
    printf '%s\torder_overwrite\t4096\t%s\tordered_entries\t%s\t%s\t%s\t0\tpass\n' \
      "$sample" "$value_bytes" "$elapsed" "$checksum" "$rss_bytes" >> "$RESULT_DIR/results.tsv"
    sample=$((sample + 1))
  done
done
fi
if [[ "$CASES" == all || "$CASES" == scans ]]; then
for count in 0 1024 4096; do
  sample=1
  while (( sample <= SAMPLES )); do
    log="$RESULT_DIR/scan-${count}-${sample}.log"
    scan_dir="$RESULT_DIR/scan-${count}-${sample}"
    [[ ! -e "$scan_dir" ]] || { echo "scan fixture already exists: $scan_dir" >&2; exit 2; }
    rss=$(MYLSM_BYTE_BENCH_SCENARIO=scan_open MYLSM_BYTE_BENCH_COUNT="$count" \
      MYLSM_BYTE_BENCH_VALUE_BYTES=32 MYLSM_BYTE_BENCH_DIR="$scan_dir" \
      python3 "$ROOT/bench/measure_rss.py" "$log" "$BINARY" --threads "$THREADS")
    row=$(grep '^scenario=' "$log")
    [[ -n "$row" ]] || { echo "missing benchmark row in $log" >&2; exit 1; }
    scenario=$(sed -n 's/.*scenario=\([^,]*\).*/\1/p' <<< "$row")
    measured_count=$(sed -n 's/.*count=\([^,]*\).*/\1/p' <<< "$row")
    value_bytes=$(sed -n 's/.*value_bytes=\([^,]*\).*/\1/p' <<< "$row")
    phase=$(sed -n 's/.*phase=\([^,]*\).*/\1/p' <<< "$row")
    elapsed=$(sed -n 's/.*elapsed_ms=\([^,]*\).*/\1/p' <<< "$row")
    checksum=$(sed -n 's/.*checksum=\([^,]*\).*/\1/p' <<< "$row")
    result=$(sed -n 's/.*result=\([^,]*\).*/\1/p' <<< "$row")
    rss_bytes=${rss#max_rss_bytes=}
    [[ "$elapsed" =~ ^[0-9]+$ && "$result" == pass && "$rss_bytes" =~ ^[0-9]+$ ]] || {
      echo "invalid scan result row in $log" >&2
      exit 1
    }
    disk_kib=$(du -sk "$scan_dir" | awk '{ print $1 }')
    disk_bytes=$((disk_kib * 1024))
    case "$scan_dir" in
      "$RESULT_DIR"/scan-*) rm -rf -- "$scan_dir" ;;
      *) echo "refusing to remove scan path outside result directory" >&2; exit 2 ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$sample" "$scenario" "$measured_count" "$value_bytes" "$phase" "$elapsed" "$checksum" "$rss_bytes" "$disk_bytes" "$result" \
      >> "$RESULT_DIR/results.tsv"
    sample=$((sample + 1))
  done
done
for count in 1024 4096; do
  for value_bytes in 32 4096; do
    sample=1
    while (( sample <= SAMPLES )); do
      log="$RESULT_DIR/scan-next-${count}-${value_bytes}-${sample}.log"
      scan_dir="$RESULT_DIR/scan-next-${count}-${value_bytes}-${sample}"
      [[ ! -e "$scan_dir" ]] || { echo "scan fixture already exists: $scan_dir" >&2; exit 2; }
      rss=$(MYLSM_BYTE_BENCH_SCENARIO=scan_delta MYLSM_BYTE_BENCH_COUNT="$count" \
        MYLSM_BYTE_BENCH_VALUE_BYTES="$value_bytes" MYLSM_BYTE_BENCH_DIR="$scan_dir" \
        python3 "$ROOT/bench/measure_rss.py" "$log" "$BINARY" --threads "$THREADS")
      row=$(grep '^scenario=' "$log")
      [[ -n "$row" ]] || { echo "missing benchmark row in $log" >&2; exit 1; }
      scenario=$(sed -n 's/.*scenario=\([^,]*\).*/\1/p' <<< "$row")
      measured_count=$(sed -n 's/.*count=\([^,]*\).*/\1/p' <<< "$row")
      measured_value_bytes=$(sed -n 's/.*value_bytes=\([^,]*\).*/\1/p' <<< "$row")
      phase=$(sed -n 's/.*phase=\([^,]*\).*/\1/p' <<< "$row")
      elapsed=$(sed -n 's/.*elapsed_ms=\([^,]*\).*/\1/p' <<< "$row")
      checksum=$(sed -n 's/.*checksum=\([^,]*\).*/\1/p' <<< "$row")
      result=$(sed -n 's/.*result=\([^,]*\).*/\1/p' <<< "$row")
      rss_bytes=${rss#max_rss_bytes=}
      [[ "$elapsed" =~ ^[0-9]+$ && "$result" == pass && "$rss_bytes" =~ ^[0-9]+$ ]] || {
        echo "invalid scan result row in $log" >&2
        exit 1
      }
      disk_kib=$(du -sk "$scan_dir" | awk '{ print $1 }')
      disk_bytes=$((disk_kib * 1024))
      case "$scan_dir" in
        "$RESULT_DIR"/scan-next-*) rm -rf -- "$scan_dir" ;;
        *) echo "refusing to remove scan path outside result directory" >&2; exit 2 ;;
      esac
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sample" "$scenario" "$measured_count" "$measured_value_bytes" "$phase" "$elapsed" "$checksum" "$rss_bytes" "$disk_bytes" "$result" \
        >> "$RESULT_DIR/results.tsv"
      sample=$((sample + 1))
    done
  done
done
fi
if [[ "$CASES" == all || "$CASES" == maintenance ]]; then
for scenario in flush compact; do
  for count in $MAINTENANCE_COUNTS; do
    case "$count" in
      ''|*[!0-9]*) echo "invalid maintenance count: $count" >&2; exit 2 ;;
    esac
    if (( count < 1 || count > 16000 )); then
      echo "maintenance count must be between 1 and 16000" >&2
      exit 2
    fi
    fixture="$FIXTURE_DIR"
    if [[ -z "$fixture" ]]; then
      fixture="$RESULT_DIR/fixture-$count"
      [[ ! -e "$fixture" ]] || { echo "maintenance fixture already exists: $fixture" >&2; exit 2; }
      prepare_log="$RESULT_DIR/fixture-$count.log"
      MYLSM_BYTE_BENCH_SCENARIO=maintenance_prepare MYLSM_BYTE_BENCH_COUNT="$count" \
        MYLSM_BYTE_BENCH_VALUE_BYTES=32 MYLSM_BYTE_BENCH_DIR="$fixture" \
        python3 "$ROOT/bench/measure_rss.py" "$prepare_log" "$BINARY" --threads "$THREADS" >/dev/null
      grep -q '^result=pass$' "$prepare_log" || grep -q ',result=pass$' "$prepare_log" || {
        echo "maintenance fixture preparation failed: $prepare_log" >&2
        exit 1
      }
    fi
    [[ -d "$fixture" && ! -L "$fixture" ]] || {
      echo "maintenance fixture is missing or is a symlink: $fixture" >&2
      exit 2
    }
    fixture=$(CDPATH= cd -- "$fixture" && pwd -P)
    sample=1
    while (( sample <= SAMPLES )); do
      log="$RESULT_DIR/${scenario}-${count}-${sample}.log"
      data_dir="$RESULT_DIR/${scenario}-${count}-${sample}"
      [[ ! -e "$data_dir" ]] || { echo "maintenance fixture already exists: $data_dir" >&2; exit 2; }
      cp -R "$fixture" "$data_dir"
      rss=$(MYLSM_BYTE_BENCH_SCENARIO="$scenario" MYLSM_BYTE_BENCH_COUNT="$count" \
        MYLSM_BYTE_BENCH_VALUE_BYTES=32 MYLSM_BYTE_BENCH_DIR="$data_dir" \
        python3 "$ROOT/bench/measure_rss.py" "$log" "$BINARY" --threads "$THREADS")
      row=$(grep '^scenario=' "$log")
      [[ -n "$row" ]] || { echo "missing maintenance result row in $log" >&2; exit 1; }
      elapsed=$(sed -n 's/.*elapsed_ms=\([^,]*\).*/\1/p' <<< "$row")
      checksum=$(sed -n 's/.*checksum=\([^,]*\).*/\1/p' <<< "$row")
      rss_bytes=${rss#max_rss_bytes=}
      [[ "$elapsed" =~ ^[0-9]+$ && "$checksum" == "$((16000 + count))" && \
        "$rss_bytes" =~ ^[0-9]+$ ]] || {
        echo "invalid maintenance result row in $log" >&2
        exit 1
      }
      disk_kib=$(du -sk "$data_dir" | awk '{ print $1 }')
      disk_bytes=$((disk_kib * 1024))
      case "$data_dir" in
        "$RESULT_DIR"/flush-*|"$RESULT_DIR"/compact-*) rm -rf -- "$data_dir" ;;
        *) echo "refusing to remove maintenance path outside result directory" >&2; exit 2 ;;
      esac
      printf '%s\t%s\t%s\t32\t%s\t%s\t%s\t%s\t%s\tpass\n' \
        "$sample" "$scenario" "$count" "$scenario" "$elapsed" "$checksum" \
        "$rss_bytes" "$disk_bytes" >> "$RESULT_DIR/results.tsv"
      sample=$((sample + 1))
    done
  done
done
fi
if [[ "$CASES" == all || "$CASES" == phases ]]; then
  fixture="$FIXTURE_DIR"
  if [[ -z "$fixture" ]]; then
    fixture="$RESULT_DIR/fixture-phases"
    [[ ! -e "$fixture" ]] || { echo "phase fixture already exists: $fixture" >&2; exit 2; }
    prepare_log="$RESULT_DIR/fixture-phases.log"
    MYLSM_BYTE_BENCH_SCENARIO=maintenance_prepare MYLSM_BYTE_BENCH_COUNT=128 \
      MYLSM_BYTE_BENCH_VALUE_BYTES=32 MYLSM_BYTE_BENCH_DIR="$fixture" \
      python3 "$ROOT/bench/measure_rss.py" "$prepare_log" "$BINARY" --threads "$THREADS" >/dev/null
    grep -q ',result=pass$' "$prepare_log" || {
      echo "phase fixture preparation failed: $prepare_log" >&2
      exit 1
    }
  fi
  [[ -d "$fixture" && ! -L "$fixture" ]] || {
    echo "phase fixture is missing or is a symlink: $fixture" >&2
    exit 2
  }
  fixture=$(CDPATH= cd -- "$fixture" && pwd -P)
  for phase in phase_read phase_order phase_encode; do
    case "$phase" in
      phase_order) phase_count=4096 ;;
      *) phase_count=16000 ;;
    esac
    sample=1
    while (( sample <= SAMPLES )); do
      log="$RESULT_DIR/${phase}-${sample}.log"
      rss=$(MYLSM_BYTE_BENCH_SCENARIO="$phase" MYLSM_BYTE_BENCH_COUNT="$phase_count" \
        MYLSM_BYTE_BENCH_VALUE_BYTES=32 MYLSM_BYTE_BENCH_DIR="$fixture" \
        python3 "$ROOT/bench/measure_rss.py" "$log" "$BINARY" --threads "$THREADS")
      row=$(grep '^scenario=' "$log")
      [[ -n "$row" ]] || { echo "missing phase result row in $log" >&2; exit 1; }
      scenario=$(sed -n 's/.*scenario=\([^,]*\).*/\1/p' <<< "$row")
      measured_count=$(sed -n 's/.*count=\([^,]*\).*/\1/p' <<< "$row")
      value_bytes=$(sed -n 's/.*value_bytes=\([^,]*\).*/\1/p' <<< "$row")
      phase_name=$(sed -n 's/.*phase=\([^,]*\).*/\1/p' <<< "$row")
      elapsed=$(sed -n 's/.*elapsed_ms=\([^,]*\).*/\1/p' <<< "$row")
      checksum=$(sed -n 's/.*checksum=\([^,]*\).*/\1/p' <<< "$row")
      result=$(sed -n 's/.*result=\([^,]*\).*/\1/p' <<< "$row")
      rss_bytes=${rss#max_rss_bytes=}
      [[ "$elapsed" =~ ^[0-9]+$ && "$result" == pass && \
        "$rss_bytes" =~ ^[0-9]+$ ]] || {
        echo "invalid phase result row in $log" >&2
        exit 1
      }
      disk_kib=$(du -sk "$fixture" | awk '{ print $1 }')
      disk_bytes=$((disk_kib * 1024))
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sample" "$scenario" "$measured_count" "$value_bytes" "$phase_name" \
        "$elapsed" "$checksum" "$rss_bytes" "$disk_bytes" "$result" \
        >> "$RESULT_DIR/results.tsv"
      sample=$((sample + 1))
    done
  done
fi
printf 'benchmark=%s\nresults=%s/results.tsv\n' "$MODE" "$RESULT_DIR"
