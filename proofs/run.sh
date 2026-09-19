#!/usr/bin/env bash

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROOF_DIR="$ROOT/proofs"
LAW_DIR="$ROOT/laws"
LOG_DIR=${MYLSM_PROOF_LOG_DIR:-"$ROOT/.mylsm/build/proofs"}
JOBS=${MYLSM_PROOF_JOBS:-4}
TIMEOUT=${MYLSM_PROOF_TIMEOUT:-900}

case "$JOBS" in
  ''|*[!0-9]*|0) echo "MYLSM_PROOF_JOBS must be a positive integer" >&2; exit 2 ;;
esac
case "$TIMEOUT" in
  ''|*[!0-9]*|0) echo "MYLSM_PROOF_TIMEOUT must be a positive integer" >&2; exit 2 ;;
esac

mkdir -p "$LOG_DIR"
TMP_ROOT=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TMP_ROOT/mylsm-proofs.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

extract_laws() {
  awk '/^[[:space:]]*law[[:space:]]+[A-Za-z0-9_]+:/ { name=$2; sub(/:$/, "", name); print name }' "$1"
}

extract_witnesses() {
  awk '/^[[:space:]]*def[[:space:]]+Laws\.[A-Za-z0-9_]+\(/ { name=$2; sub(/^Laws\./, "", name); sub(/\(.*/, "", name); print name }' "$1"
}

check_names() {
  name_error=0
  : > "$WORK/all-laws"
  : > "$WORK/all-witnesses"

  for law_file in "$LAW_DIR"/*.bend; do
    module=$(basename "$law_file" .bend)
    proof_file="$PROOF_DIR/${module}Proof.bend"
    if [ ! -f "$proof_file" ]; then
      echo "NAME FAIL $module: missing proofs/${module}Proof.bend" >&2
      name_error=1
      continue
    fi

    extract_laws "$law_file" > "$WORK/$module.laws"
    extract_witnesses "$proof_file" > "$WORK/$module.witnesses"
    cat "$WORK/$module.laws" >> "$WORK/all-laws"
    cat "$WORK/$module.witnesses" >> "$WORK/all-witnesses"

    sort "$WORK/$module.laws" > "$WORK/$module.laws.sorted"
    sort "$WORK/$module.witnesses" > "$WORK/$module.witnesses.sorted"

    duplicates=$(uniq -d "$WORK/$module.laws.sorted")
    if [ -n "$duplicates" ]; then
      echo "NAME FAIL $module: duplicate laws: $duplicates" >&2
      name_error=1
    fi
    duplicates=$(uniq -d "$WORK/$module.witnesses.sorted")
    if [ -n "$duplicates" ]; then
      echo "NAME FAIL $module: duplicate witnesses: $duplicates" >&2
      name_error=1
    fi

    missing=$(comm -23 "$WORK/$module.laws.sorted" "$WORK/$module.witnesses.sorted")
    extra=$(comm -13 "$WORK/$module.laws.sorted" "$WORK/$module.witnesses.sorted")
    if [ -n "$missing" ]; then
      echo "NAME FAIL $module: missing witnesses: $missing" >&2
      name_error=1
    fi
    if [ -n "$extra" ]; then
      echo "NAME FAIL $module: extra witnesses: $extra" >&2
      name_error=1
    fi
  done

  for proof_file in "$PROOF_DIR"/*Proof.bend; do
    module=$(basename "$proof_file" Proof.bend)
    if [ ! -f "$LAW_DIR/$module.bend" ]; then
      echo "NAME FAIL $module: missing laws/$module.bend" >&2
      name_error=1
    fi
  done

  sort "$WORK/all-laws" > "$WORK/all-laws.sorted"
  sort "$WORK/all-witnesses" > "$WORK/all-witnesses.sorted"
  duplicates=$(uniq -d "$WORK/all-laws.sorted")
  if [ -n "$duplicates" ]; then
    echo "NAME FAIL global: duplicate law names: $duplicates" >&2
    name_error=1
  fi
  duplicates=$(uniq -d "$WORK/all-witnesses.sorted")
  if [ -n "$duplicates" ]; then
    echo "NAME FAIL global: duplicate witness names: $duplicates" >&2
    name_error=1
  fi

  if [ "$name_error" -ne 0 ]; then
    return 1
  fi
  echo "NAME PASS: laws and witnesses match exactly"
}

run_with_timeout() {
  proof_file=$1
  log_file=$2
  timeout_marker=$3

  bend "$proof_file" > "$log_file" 2>&1 &
  bend_pid=$!
  (
    sleep "$TIMEOUT"
    if kill -0 "$bend_pid" 2>/dev/null; then
      : > "$timeout_marker"
      kill "$bend_pid" 2>/dev/null || true
      sleep 2
      kill -9 "$bend_pid" 2>/dev/null || true
    fi
  ) &
  timer_pid=$!

  wait "$bend_pid"
  result=$?
  kill "$timer_pid" 2>/dev/null || true
  wait "$timer_pid" 2>/dev/null || true
  return "$result"
}

if ! check_names; then
  exit 1
fi

proofs=("$PROOF_DIR"/*Proof.bend)
total=${#proofs[@]}
passed=0
failed=0
timed_out=0
index=0

while [ "$index" -lt "$total" ]; do
  batch_pids=()
  batch_names=()
  batch_logs=()
  batch_markers=()
  launched=0

  while [ "$launched" -lt "$JOBS" ] && [ "$index" -lt "$total" ]; do
    proof_file=${proofs[$index]}
    module=$(basename "$proof_file" Proof.bend)
    log_file="$LOG_DIR/$module.log"
    marker="$WORK/$module.timeout"
    rm -f "$marker"
    : > "$log_file"
    run_with_timeout "$proof_file" "$log_file" "$marker" &
    batch_pids[$launched]=$!
    batch_names[$launched]=$module
    batch_logs[$launched]=$log_file
    batch_markers[$launched]=$marker
    launched=$((launched + 1))
    index=$((index + 1))
  done

  current=0
  while [ "$current" -lt "$launched" ]; do
    pid=${batch_pids[$current]}
    module=${batch_names[$current]}
    log_file=${batch_logs[$current]}
    marker=${batch_markers[$current]}
    wait "$pid"
    result=$?
    if [ -f "$marker" ]; then
      echo "TIMEOUT $module (${TIMEOUT}s; log: $log_file)"
      timed_out=$((timed_out + 1))
    elif [ "$result" -eq 0 ]; then
      echo "PASS    $module (log: $log_file)"
      passed=$((passed + 1))
    else
      echo "FAIL    $module (exit $result; log: $log_file)"
      failed=$((failed + 1))
    fi
    current=$((current + 1))
  done
done

echo "SUMMARY PASS=$passed FAIL=$failed TIMEOUT=$timed_out TOTAL=$total"
if [ "$failed" -ne 0 ] || [ "$timed_out" -ne 0 ]; then
  exit 1
fi
