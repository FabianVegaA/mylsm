#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DB=$(mktemp -d /tmp/mylsm-unix-socket.XXXXXX)
trap 'rm -rf "$DB"' EXIT

bend "$ROOT/bench/smoke/unix_socket.bend" -o "$DB/unix-socket"
MYLSM_DB_PATH="$DB" "$DB/unix-socket"
bend "$ROOT/bench/smoke/unix_socket_unsupported.bend"
