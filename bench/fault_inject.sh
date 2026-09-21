#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
MODE=run
case "${1:-}" in
  --self-test|--validate-only)
    MODE=${1#--}
    shift
    ;;
esac

REQUESTED_OUTPUT=${1:-"$ROOT/.mylsm-crash-injection"}
REPETITIONS=${MYLSM_CRASH_REPETITIONS:-3}
STOP_TIMEOUT=${MYLSM_CRASH_STOP_TIMEOUT:-10}
BUILD_DIR="$ROOT/.mylsm/build"
BINARY="$BUILD_DIR/crash-worker"
SOURCE="$ROOT/bench/crash_worker.bend"
CURRENT_PID=
CURRENT_ARTIFACT_DIR=
MATRIX_COMPLETE=0
SENTINEL_NAME=.mylsm-crash-harness
SENTINEL_CONTENT=mylsm-crash-injection-v1

require_supported_os() {
  case "$1" in
    Darwin|Linux) return 0 ;;
    *) echo "unsupported crash-injection platform: $1" >&2; return 2 ;;
  esac
}

positive_integer() {
  case "$2" in
    ''|*[!0-9]*|0) echo "$1 must be a positive integer" >&2; return 2 ;;
  esac
}

validate_output_root() {
  local requested=$1
  local parent name canonical

  case "$requested" in
    ''|/) echo "refusing unsafe crash output root: ${requested:-<empty>}" >&2; return 2 ;;
  esac
  [[ ! -L "$requested" ]] || { echo "refusing symlink crash output root: $requested" >&2; return 2; }

  parent=$(dirname -- "$requested")
  name=$(basename -- "$requested")
  case "$name" in
    ''|.|..) echo "refusing unsafe crash output root: $requested" >&2; return 2 ;;
  esac
  [[ -d "$parent" ]] || { echo "crash output parent does not exist: $parent" >&2; return 2; }
  parent=$(CDPATH= cd -- "$parent" && pwd -P)
  canonical="$parent/$name"

  [[ "$canonical" != / && "$canonical" != "$ROOT" && "$canonical" != "$HOME" ]] || {
    echo "refusing unsafe crash output root: $canonical" >&2
    return 2
  }
  [[ "$parent" == "$ROOT" ]] || { echo "crash output root must be a direct child of $ROOT" >&2; return 2; }
  case "$name" in
    .mylsm-crash-*) ;;
    *) echo "crash output root must start with .mylsm-crash-" >&2; return 2 ;;
  esac
  [[ ! -L "$canonical" ]] || { echo "refusing symlink crash output root: $canonical" >&2; return 2; }
  printf '%s\n' "$canonical"
}

prepare_output_root() {
  local output=$1
  if [[ -e "$output" ]]; then
    [[ ${MYLSM_CRASH_RESET:-0} == 1 ]] || {
      echo "crash output root already exists: $output" >&2
      echo "Set MYLSM_CRASH_RESET=1 to remove it." >&2
      return 2
    }
    [[ -d "$output" ]] || { echo "crash output root is not a directory: $output" >&2; return 2; }
    [[ -f "$output/$SENTINEL_NAME" ]] || { echo "refusing unowned crash output root: $output" >&2; return 2; }
    grep -qxF "$SENTINEL_CONTENT" "$output/$SENTINEL_NAME" || { echo "invalid crash output sentinel: $output" >&2; return 2; }
    rm -rf -- "$output"
  fi
  mkdir -p -- "$output"
  printf '%s\n' "$SENTINEL_CONTENT" >"$output/$SENTINEL_NAME"
}

run_self_test() {
  local work link existing
  work=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-crash-self-test.XXXXXX")
  link="$work/link"
  existing="$work/existing"
  mkdir -p -- "$existing"
  ln -s "$existing" "$link"

  ! validate_output_root "" >/dev/null 2>&1
  ! validate_output_root / >/dev/null 2>&1
  ! validate_output_root "$ROOT" >/dev/null 2>&1
  ! validate_output_root "$HOME" >/dev/null 2>&1
  ! validate_output_root "$ROOT/src" >/dev/null 2>&1
  ! validate_output_root "$HOME/.mylsm-crash-test" >/dev/null 2>&1
  ! validate_output_root "$link" >/dev/null 2>&1
  ! require_supported_os FreeBSD >/dev/null 2>&1
  unset MYLSM_CRASH_RESET
  ! prepare_output_root "$existing" >/dev/null 2>&1
  test -d "$existing"
  MYLSM_CRASH_RESET=1
  ! prepare_output_root "$existing" >/dev/null 2>&1
  printf '%s\n' wrong-sentinel >"$existing/$SENTINEL_NAME"
  ! prepare_output_root "$existing" >/dev/null 2>&1
  printf '%s\n' "$SENTINEL_CONTENT" >"$existing/$SENTINEL_NAME"
  prepare_output_root "$existing"
  grep -qxF "$SENTINEL_CONTENT" "$existing/$SENTINEL_NAME"
  unset MYLSM_CRASH_RESET

  rm -rf -- "$work"
  echo "self_test_status=pass unsafe_paths=pass unsupported_platform=pass reset_guard=pass"
}

wait_for_stop() {
  local pid=$1
  local deadline=$((SECONDS + STOP_TIMEOUT))
  local state
  while (( SECONDS < deadline )); do
    state=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)
    case "$state" in
      T*) return 0 ;;
    esac
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "worker exited before SIGSTOP pid=$pid state=${state:-missing}" >&2
      return 1
    fi
    sleep 0.05
  done
  echo "timed out waiting for SIGSTOP pid=$pid timeout_seconds=$STOP_TIMEOUT" >&2
  return 124
}

checkpoint_config() {
  case "$1" in
    wal.appended) echo "wal optional 0 0 3" ;;
    wal.synced) echo "wal required 0 0 3" ;;
    flush.table_synced|flush.table_published|flush.manifest_synced) echo "flush absent 0 0 4" ;;
    flush.manifest_published) echo "flush absent 1 0 4" ;;
    compact.output_synced|compact.output_published|compact.manifest_synced) echo "compact absent 5 0 15" ;;
    compact.manifest_published) echo "compact absent 0 1 15" ;;
    *) echo "unknown checkpoint: $1" >&2; return 2 ;;
  esac
}

on_exit() {
  local rc=$?
  if [[ -n ${CURRENT_PID:-} ]] && kill -0 "$CURRENT_PID" 2>/dev/null; then
    kill -9 "$CURRENT_PID" 2>/dev/null || true
    wait "$CURRENT_PID" 2>/dev/null || true
  fi
  if [[ "$MODE" == run && ( "$rc" -ne 0 || "$MATRIX_COMPLETE" -ne 1 ) ]]; then
    echo "matrix_status=fail artifacts=${CURRENT_ARTIFACT_DIR:-$OUTPUT_ROOT}" >&2
  fi
  exit "$rc"
}

run_case() {
  local checkpoint=$1 repetition=$2
  local config case_name trigger expected_l0 expected_l1 acknowledged
  local case_dir db_dir prepare_log crash_log verify_log kill_status

  config=$(checkpoint_config "$checkpoint")
  read -r case_name trigger expected_l0 expected_l1 acknowledged <<<"$config"
  case_dir="$OUTPUT_ROOT/cases/$checkpoint/rep-$repetition"
  db_dir="$case_dir/db"
  prepare_log="$case_dir/prepare.log"
  crash_log="$case_dir/crash.log"
  verify_log="$case_dir/verify.log"
  CURRENT_ARTIFACT_DIR=$case_dir
  mkdir -p -- "$case_dir"

  env -u MYLSM_CRASH_POINT \
    MYLSM_CRASH_MODE=prepare \
    MYLSM_CRASH_CASE="$case_name" \
    MYLSM_CRASH_DIR="$db_dir" \
    "$BINARY" --threads "$THREADS" >"$prepare_log" 2>&1
  grep -q "^worker_mode=prepare case=$case_name status=complete acknowledged_keys=$acknowledged$" "$prepare_log"

  MYLSM_CRASH_MODE=run \
    MYLSM_CRASH_CASE="$case_name" \
    MYLSM_CRASH_DIR="$db_dir" \
    MYLSM_CRASH_POINT="$checkpoint" \
    "$BINARY" --threads "$THREADS" >"$crash_log" 2>&1 &
  CURRENT_PID=$!

  wait_for_stop "$CURRENT_PID"
  grep -qxF "crash_point_reached=$checkpoint" "$crash_log"
  grep -q "^worker_mode=run case=$case_name status=armed$" "$crash_log"
  ! grep -q "^worker_mode=run case=$case_name status=complete$" "$crash_log"

  kill -9 "$CURRENT_PID"
  set +e
  wait "$CURRENT_PID"
  kill_status=$?
  set -e
  CURRENT_PID=
  [[ "$kill_status" -eq 137 ]] || { echo "expected kill status 137, got $kill_status" >&2; return 1; }

  env -u MYLSM_CRASH_POINT \
    MYLSM_CRASH_MODE=verify \
    MYLSM_CRASH_CASE="$case_name" \
    MYLSM_CRASH_DIR="$db_dir" \
    MYLSM_EXPECT_TRIGGER="$trigger" \
    MYLSM_EXPECT_L0="$expected_l0" \
    MYLSM_EXPECT_L1="$expected_l1" \
    "$BINARY" --threads "$THREADS" >"$verify_log" 2>&1
  grep -q "^worker_mode=verify case=$case_name reopen=1 keys=pass level_shape=pass referenced_data=pass$" "$verify_log"
  grep -q "^worker_mode=verify case=$case_name reopen=2 keys=pass level_shape=pass referenced_data=pass$" "$verify_log"
  grep -q "^worker_mode=verify case=$case_name status=complete reopen_stability=pass$" "$verify_log"

  rm -rf -- "$db_dir"
  echo "case=$checkpoint repetition=$repetition stopped=pass kill_status=137 recovery=pass reopen_stability=pass level_shape=pass"
}

PLATFORM=$(uname -s)
require_supported_os "$PLATFORM"
positive_integer MYLSM_CRASH_REPETITIONS "$REPETITIONS"
positive_integer MYLSM_CRASH_STOP_TIMEOUT "$STOP_TIMEOUT"

if [[ -n ${MYLSM_THREADS:-} ]]; then
  THREADS=$MYLSM_THREADS
elif [[ "$PLATFORM" == Darwin ]]; then
  THREADS=$(sysctl -n hw.logicalcpu)
elif command -v nproc >/dev/null 2>&1; then
  THREADS=$(nproc)
else
  THREADS=1
fi
positive_integer MYLSM_THREADS "$THREADS"
(( THREADS >= 1 && THREADS <= 256 )) || { echo "MYLSM_THREADS must be between 1 and 256" >&2; exit 2; }

if [[ "$MODE" == self-test ]]; then
  run_self_test
  exit 0
fi

OUTPUT_ROOT=$(validate_output_root "$REQUESTED_OUTPUT")
if [[ "$MODE" == validate-only ]]; then
  echo "validation_status=pass platform=$PLATFORM repetitions=$REPETITIONS output_root=$OUTPUT_ROOT"
  exit 0
fi

for command_name in bend ps grep awk sed tr; do
  command -v "$command_name" >/dev/null 2>&1 || { echo "$command_name is required" >&2; exit 127; }
done

prepare_output_root "$OUTPUT_ROOT"
trap on_exit EXIT HUP INT TERM
RESULT_LOG="$OUTPUT_ROOT/matrix.log"
exec > >(tee "$RESULT_LOG") 2>&1

mkdir -p -- "$BUILD_DIR"
echo "phase=build status=starting source=$SOURCE"
bend "$SOURCE" -o "$BINARY"
[[ -x "$BINARY" ]] || { echo "native crash worker was not produced: $BINARY" >&2; exit 1; }
echo "phase=build status=complete binary=$BINARY"

echo "bend_version=$(bend version)"
echo "platform=$PLATFORM architecture=$(uname -m) threads=$THREADS repetitions=$REPETITIONS"

CHECKPOINTS=(
  wal.appended
  wal.synced
  flush.table_synced
  flush.table_published
  flush.manifest_synced
  flush.manifest_published
  compact.output_synced
  compact.output_published
  compact.manifest_synced
  compact.manifest_published
)

completed_cases=0
for checkpoint in "${CHECKPOINTS[@]}"; do
  for ((repetition = 1; repetition <= REPETITIONS; repetition++)); do
    run_case "$checkpoint" "$repetition"
    completed_cases=$((completed_cases + 1))
  done
done

expected_cases=$((10 * REPETITIONS))
[[ "$completed_cases" -eq "$expected_cases" ]]
MATRIX_COMPLETE=1
echo "matrix_status=pass checkpoints=10 repetitions=$REPETITIONS cases=$completed_cases platform=$PLATFORM"
