#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-generation-tokens.XXXXXX")
DB="$WORK/db"
OWNER_PID=
OLD_PID=
NEW_PID=

cleanup() {
  local status=$?
  if ((status != 0)); then
    for diagnostic in "$WORK/owner.log" "$WORK/old-client.err" "$WORK/new-client.err"; do
      if [[ -f "$diagnostic" ]]; then
        cat "$diagnostic"
      fi
    done
  fi
  if [[ -n "$OWNER_PID" ]]; then
    kill -KILL "$OWNER_PID" 2>/dev/null || true
    wait "$OWNER_PID" 2>/dev/null || true
  fi
  if [[ -n "$OLD_PID" ]]; then
    kill "$OLD_PID" 2>/dev/null || true
    wait "$OLD_PID" 2>/dev/null || true
  fi
  if [[ -n "$NEW_PID" ]]; then
    kill "$NEW_PID" 2>/dev/null || true
    wait "$NEW_PID" 2>/dev/null || true
  fi
  if ((status != 0)) && [[ "${MYLSM_KEEP_TEST_TMP:-0}" == "1" ]]; then
    printf 'OWNER_GENERATION_TOKEN_FIXTURE_TMP=%s\n' "$WORK"
    return "$status"
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

bend "$ROOT/bench/smoke/owner_generation_create.bend" -o "$WORK/create"
bend "$ROOT/bench/smoke/owner_generation_tokens.bend" -o "$WORK/client"
bend "$ROOT/app/owner/mylsm_owner.bend" -o "$WORK/owner"
MYLSM_DB_PATH="$DB" "$WORK/create"
mkfifo "$WORK/old.ready" "$WORK/new.ready"
exec 4<>"$WORK/old.ready"
exec 5<>"$WORK/new.ready"

start_owner() {
  local expected_generation="$1"
  local previous_socket_id="$2"
  local current_generation=
  local current_socket_id=
  MYLSM_DB_PATH="$DB" "$WORK/owner" >"$WORK/owner.log" 2>&1 &
  OWNER_PID=$!
  for ((attempt = 0; attempt < 100000; attempt += 1)); do
    if [[ -S "$DB/MYLSM.sock" ]]; then
      current_generation=$(generation_hex)
      current_socket_id=$(ls -di "$DB/MYLSM.sock" 2>/dev/null | awk '{print $1}')
      if [[ "$current_generation" == "$expected_generation" &&
        "$current_socket_id" != "$previous_socket_id" ]]; then
        return
      fi
    fi
    if ! kill -0 "$OWNER_PID" 2>/dev/null; then
      cat "$WORK/owner.log"
      exit 1
    fi
  done
  cat "$WORK/owner.log"
  exit 1
}

generation_hex() {
  od -An -tx1 "$DB/OWNER.GEN" | tr -d ' \n'
}

read_until() {
  local file_descriptor="$1"
  local expected="$2"
  local line=
  for ((attempt = 0; attempt < 8; attempt += 1)); do
    if ! IFS= read -r -t 5 -u "$file_descriptor" line; then
      return 1
    fi
    if [[ "$line" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

read_ready_pipe() {
  local file_descriptor="$1"
  local count="$2"
  local line=
  for ((attempt = 0; attempt < count; attempt += 1)); do
    if ! IFS= read -r -t 15 -u "$file_descriptor" line; then
      printf 'OWNER_GENERATION_TOKEN_READINESS_TIMEOUT=%d/%d\n' \
        "$attempt" "$count" >&2
      return 1
    fi
    if [[ "$line" != "ready" ]]; then
      printf 'OWNER_GENERATION_TOKEN_READINESS_INVALID=%s\n' "$line" >&2
      return 1
    fi
  done
}

stop_owner() {
  kill -KILL "$OWNER_PID"
  wait "$OWNER_PID" 2>/dev/null || true
  OWNER_PID=
}

start_owner "00000001" ""
[[ "$(generation_hex)" == "00000001" ]]
first_socket_id=$(ls -di "$DB/MYLSM.sock" | awk '{print $1}')
set +e
MYLSM_DB_PATH="$DB" "$WORK/owner" >"$WORK/contender.log" 2>&1
contender_status=$?
set -e
if ((contender_status == 0)); then
  printf '%s\n' 'second owner acquired an already-held database lock' >&2
  exit 1
fi
kill -0 "$OWNER_PID"
[[ "$(generation_hex)" == "00000001" ]]
[[ "$(ls -di "$DB/MYLSM.sock" | awk '{print $1}')" == "$first_socket_id" ]]
coproc OLD_CLIENT {
  MYLSM_DB_PATH="$DB" MYLSM_OWNER_TOKEN_MODE=old \
    MYLSM_READY_PIPE_PATH="$WORK/old.ready" \
    "$WORK/client" 2>"$WORK/old-client.err"
}
OLD_PID=$OLD_CLIENT_PID
exec {OLD_OUT}<&"${OLD_CLIENT[0]}" {OLD_IN}>&"${OLD_CLIENT[1]}"
read_ready_pipe 4 4
old_socket_id=$(ls -di "$DB/MYLSM.sock" | awk '{print $1}')
stop_owner

start_owner "00000002" "$old_socket_id"
[[ "$(generation_hex)" == "00000002" ]]
coproc NEW_CLIENT {
  MYLSM_DB_PATH="$DB" MYLSM_OWNER_TOKEN_MODE=new \
    MYLSM_READY_PIPE_PATH="$WORK/new.ready" \
    "$WORK/client" 2>"$WORK/new-client.err"
}
NEW_PID=$NEW_CLIENT_PID
exec {NEW_OUT}<&"${NEW_CLIENT[0]}" {NEW_IN}>&"${NEW_CLIENT[1]}"
read_ready_pipe 5 4

printf '%s\n' continue >&"$OLD_IN"
read_until "$OLD_OUT" "OWNER_GENERATION_PUBLIC_TOKENS_REJECTED"
wait "$OLD_PID"
OLD_PID=

printf '%s\n' continue >&"$NEW_IN"
read_until "$NEW_OUT" "OWNER_GENERATION_NEW_PUBLIC_TOKENS_VALID"
wait "$NEW_PID"
NEW_PID=
stop_owner
printf '%s\n' OWNER_GENERATION_PUBLIC_TOKENS_PASSED
