#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-unix-permission.XXXXXX")
trap 'chmod 700 "$DB"; rm -rf "$DB"' EXIT

bend "$ROOT/bench/smoke/unix_socket_permissions.bend" -o "$DB/check"
chmod 500 "$DB"
MYLSM_DB_PATH="$DB" "$DB/check"
