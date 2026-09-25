#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD="$ROOT/.mylsm/build/crash-point-smoke"
JS_BUILD="$ROOT/.mylsm/build/crash-point-smoke.js"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-crash-smoke.XXXXXX")
PID=

cleanup() {
  local rc=$?
  if [[ -n ${PID:-} ]] && kill -0 "$PID" 2>/dev/null; then
    kill -9 "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf -- "$WORK"
  exit "$rc"
}
trap cleanup EXIT HUP INT TERM

wait_for_stop() {
  local pid=$1
  local deadline=$((SECONDS + 10))
  local state

  while (( SECONDS < deadline )); do
    state=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)
    case "$state" in
      T*) return 0 ;;
    esac
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 0.05
  done
  return 124
}

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) echo "unsupported platform" >&2; exit 2 ;;
esac

mkdir -p -- "$ROOT/.mylsm/build"

unset MYLSM_CRASH_POINT
bend "$ROOT/bench/smoke/crash_point.bend" >"$WORK/unset.log"
grep -q '^crash_point_smoke_program=complete$' "$WORK/unset.log"

MYLSM_CRASH_POINT=other.point bend "$ROOT/bench/smoke/crash_point.bend" >"$WORK/mismatch.log"
grep -q '^crash_point_smoke_program=complete$' "$WORK/mismatch.log"

bend "$ROOT/bench/smoke/crash_point.bend" -o "$JS_BUILD"
MYLSM_CRASH_POINT=smoke.stop node "$JS_BUILD" >"$WORK/js-match.log" 2>&1 &
PID=$!
wait_for_stop "$PID"
grep -qxF 'crash_point_reached=smoke.stop' "$WORK/js-match.log"
kill -9 "$PID"
set +e
wait "$PID"
js_status=$?
set -e
PID=
[[ "$js_status" -eq 137 ]]
! grep -q '^crash_point_smoke_program=complete$' "$WORK/js-match.log"

bend "$ROOT/bench/smoke/crash_point.bend" -o "$BUILD"
MYLSM_CRASH_POINT=smoke.stop "$BUILD" --threads 1 >"$WORK/native-match.log" 2>&1 &
PID=$!
wait_for_stop "$PID"
grep -qxF 'crash_point_reached=smoke.stop' "$WORK/native-match.log"
kill -9 "$PID"
set +e
wait "$PID"
native_status=$?
set -e
PID=
[[ "$native_status" -eq 137 ]]
! grep -q '^crash_point_smoke_program=complete$' "$WORK/native-match.log"

echo "crash_point_smoke=pass unset=pass mismatch=pass js_matching_stop=pass native_matching_stop=pass kill_status=137"
