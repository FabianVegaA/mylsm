#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-owner-socket.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
DB="$WORK/db"

bend "$ROOT/bench/smoke/coordinator_owner_socket.bend" -o "$WORK/owner-socket"
MYLSM_DB_PATH="$DB" "$WORK/owner-socket"
