#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build/durable-session"
BINARY="$BUILD_DIR/durable_session"
SOURCE="$ROOT/bench/smoke/durable_session.bend"
DB="$BUILD_DIR/db"

mkdir -p -- "$BUILD_DIR"
bend "$SOURCE" -o "$BINARY"
rm -rf -- "$DB"
MYLSM_DB_PATH="$DB" MYLSM_SESSION_MODE=create "$BINARY" > "$BUILD_DIR/create.log"
grep -qx SESSION_CLOSE_CASES "$BUILD_DIR/create.log"
grep -qx SESSION_OPEN_REQUIRES_EXISTING_DATABASE "$BUILD_DIR/create.log"
grep -qx SESSION_CREATED "$BUILD_DIR/create.log"
grep -qx SESSION_CREATE_REJECTS_EXISTING_DATABASE "$BUILD_DIR/create.log"
MYLSM_DB_PATH="$DB" MYLSM_SESSION_MODE=open "$BINARY" > "$BUILD_DIR/open.log"
grep -qx SESSION_RECOVERED "$BUILD_DIR/open.log"
grep -qx SESSION_STOPPED_ON_ERROR "$BUILD_DIR/open.log"
grep -qx SESSION_RELEASED_AFTER_ERROR "$BUILD_DIR/open.log"
grep -qx SESSION_HANDLE_RETAINED "$BUILD_DIR/open.log"

printf '%s\n' 'DURABLE SESSION PASS'
