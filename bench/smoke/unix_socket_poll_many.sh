#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-poll-many.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
bend "$ROOT/bench/smoke/unix_socket_poll_many.bend" -o "$BUILD/unix_socket_poll_many"
MYLSM_POLL_FIRST="$BUILD/first.sock" \
MYLSM_POLL_SECOND="$BUILD/second.sock" \
  "$BUILD/unix_socket_poll_many"
